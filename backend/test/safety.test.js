const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

if (process.env.TEST_DATABASE_URL) {
  const dbName = new URL(process.env.TEST_DATABASE_URL).pathname.split('/').filter(Boolean).pop() || '';
  if (!/(^|_)test($|_)/i.test(dbName)) throw new Error('Refusing PostgreSQL tests unless database name includes "test"');
  process.env.DB_CLIENT = 'pg';
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
} else {
  process.env.DB_CLIENT = 'better-sqlite3';
  process.env.SQLITE_FILE = process.env.TEST_SQLITE_FILE || path.join(os.tmpdir(), `vktrix-safety-${process.pid}.sqlite`);
  for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
}
process.env.JWT_SECRET = 'isolated-test-secret-never-use-in-production';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';

const root = path.resolve(__dirname, '..');
const express = require('express');
const jwt = require('jsonwebtoken');
const db = require('../src/db');
const migrate = require('../src/migrate');

const date = '2024-01-01';
const saleDate = '2024-01-02';
const imei = '490154203237518';
const validImei2 = '353328110000005';
let server;
let base;

async function request(method, route, token, data) {
  const response = await fetch(base + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(data === undefined ? {} : { body: JSON.stringify(data) }),
  });
  return { status: response.status, body: await response.json() };
}
async function login(username, password) {
  const r = await request('POST', '/auth/login', null, { username, password });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.token;
}
async function buy(token, overrides = {}) {
  return request('POST', '/buy', token, {
    imei, brand: 'Test', model: 'Phone', condition: 'Good', buy_price: '100.00', buy_date: date, ...overrides,
  });
}

test('sale validation, locking, tenant scope, snapshots and token revocation', async t => {
  await migrate();
  // This file is either a new SQLite temp DB or a PostgreSQL database explicitly
  // named *_test. Remove only application rows from that isolated test DB.
  await db('sales').del();
  await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del();
  await db('shops').del();
  await migrate(); // also asserts the additive migration is idempotent.

  const app = express();
  app.use(express.json());
  app.use('/api/auth', require('../src/routes/auth'));
  app.use('/api/admin', require('../src/routes/admin'));
  app.use('/api', require('../src/routes/shop'));
  app.use((err, req, res, next) => res.status(err.status || 500).json({ error: err.message }));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}/api`;
  t.after(async () => {
    await new Promise(resolve => server.close(resolve));
    await db.destroy();
    if (!process.env.TEST_DATABASE_URL) {
      for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
    }
  });

  const admin = await login('superadmin', 'AuditOnly@123');
  const a = await request('POST', '/admin/shops', admin, { name: 'Alpha Shop', username: 'ownerA', password: 'OwnerA@123' });
  const b = await request('POST', '/admin/shops', admin, { name: 'Beta Shop', username: 'ownerB', password: 'OwnerB@123' });
  assert.equal(a.status, 200); assert.equal(b.status, 200);
  let shopA = await login('ownerA', 'OwnerA@123');
  let shopB = await login('ownerB', 'OwnerB@123');

  await t.test('validates positive money, dates, IDs, enum and both IMEIs at API boundary', async () => {
    for (const payload of [
      { buy_price: '-1' }, { buy_price: '0' }, { buy_price: 'NaN' }, { buy_price: '12.345' },
      { imei2: '12345' }, { imei2: imei }, { buy_date: '2024-02-30' }, { condition: 'Unknown' },
      { unexpected: 'field' },
    ]) {
      const r = await buy(shopA, payload);
      assert.equal(r.status, 400, JSON.stringify({ payload, result: r }));
    }
    const invalidId = await request('POST', '/sell', shopA, { phone_id: '1 OR 1=1', sell_price: 100 });
    assert.equal(invalidId.status, 400);
    for (const payload of [
      { sell_price: '-1' }, { sell_price: '0' }, { sell_price: '12.345' },
      { sell_price: '100', payment_mode: 'crypto' }, { sell_price: '100', sell_date: '2024-02-30' },
      { sell_price: '100', customer_phone: 'abc' },
    ]) {
      const r = await request('POST', '/sell', shopA, { phone_id: 1, ...payload });
      assert.equal(r.status, 400, JSON.stringify({ payload, result: r }));
    }
    const badRange = await request('GET', '/reports/summary?from=2024-02-01&to=2024-01-01', shopA);
    assert.equal(badRange.status, 400);
  });

  let phoneA, phoneB;
  await t.test('record IDs stay tenant-scoped; same IMEI in another shop is a different row', async () => {
    const pa = await buy(shopA, { imei2: validImei2 });
    const pb = await buy(shopB);
    assert.equal(pa.status, 200, JSON.stringify(pa.body));
    assert.equal(pb.status, 200, JSON.stringify(pb.body));
    phoneA = pa.body.id; phoneB = pb.body.id;
    assert.notEqual(phoneA, phoneB);
    const lookupSecondary = await request('GET', `/imei/${validImei2}`, shopA);
    assert.equal(lookupSecondary.body.already_in_stock, true);
    assert.equal(lookupSecondary.body.history[0].id, phoneA);
    const duplicateSecondary = await buy(shopA, { imei: validImei2, imei2: undefined });
    assert.equal(duplicateSecondary.status, 400);
    const forged = await request('GET', `/stock?shop_id=${b.body.id}`, shopA);
    assert.equal(forged.status, 200);
    assert.deepEqual(forged.body.map(x => x.id), [phoneA]);
    const crossRead = await request('GET', `/phones/${phoneB}`, shopA);
    assert.equal(crossRead.status, 404);
    const crossSell = await request('POST', '/sell', shopA, { phone_id: phoneB, sell_price: 300, sell_date: saleDate });
    assert.equal(crossSell.status, 409);
    const beforePurchase = await request('POST', '/sell', shopA,
      { phone_id: phoneA, sell_price: 200, sell_date: '2023-12-31' });
    assert.equal(beforePurchase.status, 400);
  });

  await t.test('only one concurrent sale can win and profit uses immutable purchase cost', async () => {
    const attempts = await Promise.all(Array.from({ length: 12 }, () =>
      request('POST', '/sell', shopA, { phone_id: phoneA, sell_price: '300.00', sell_date: saleDate, payment_mode: 'upi' })));
    assert.equal(attempts.filter(x => x.status === 200).length, 1, JSON.stringify(attempts));
    assert.equal(attempts.filter(x => x.status === 409).length, 11, JSON.stringify(attempts));
    const sales = await request('GET', '/sales', shopA);
    assert.equal(sales.status, 200); assert.equal(sales.body.length, 1);
    assert.equal(Number(sales.body[0].buy_price), 100);
    const changedCost = await request('PUT', `/phones/${phoneA}`, shopA, { buy_price: '250.00' });
    assert.equal(changedCost.status, 200);
    const summary = await request('GET', '/reports/summary?from=2024-01-01&to=2024-01-02', shopA);
    assert.equal(Number(summary.body.sales.profit), 200, JSON.stringify(summary.body));
    const daily = await request('GET', '/reports/daily?from=2024-01-01&to=2024-01-02', shopA);
    assert.equal(daily.status, 200); assert.equal(Number(daily.body[0].profit), 200);
    const secondSale = await request('POST', '/sell', shopA, { phone_id: phoneA, sell_price: '300', sell_date: saleDate });
    assert.equal(secondSale.status, 409);
    const cancelForeign = await request('DELETE', `/sales/${sales.body[0].id}`, shopB);
    assert.equal(cancelForeign.status, 404);
    const cancelled = await request('DELETE', `/sales/${sales.body[0].id}`, shopA);
    assert.equal(cancelled.status, 200);
    const restored = await request('GET', '/stock', shopA);
    assert.ok(restored.body.some(p => p.id === phoneA));
    const missingUpdate = await request('PUT', '/phones/2147483647', shopA, { model: 'No row' });
    assert.equal(missingUpdate.status, 404);
    const missingCancel = await request('DELETE', '/sales/2147483647', shopA);
    assert.equal(missingCancel.status, 404);
  });

    await t.test('password change and admin reset revoke old JWTs; pre-version tokens migrate safely', async () => {
      const legacy = jwt.sign({ id: (await db('users').where({ username: 'ownerA' }).first()).id,
        role: 'shop_admin', shop_id: Number(a.body.id) }, process.env.JWT_SECRET, { expiresIn: '1h' });
      assert.equal((await request('GET', '/stock', legacy)).status, 200);
      const changed = await request('POST', '/auth/change-password', shopA,
        { old_password: 'OwnerA@123', new_password: 'OwnerA@456' });
      assert.equal(changed.status, 200, JSON.stringify(changed.body));
      assert.equal(changed.body.session_revoked, true);
      assert.equal((await request('GET', '/stock', shopA)).status, 401);
      shopA = await login('ownerA', 'OwnerA@456');

      const reset = await request('POST', `/admin/shops/${b.body.id}/reset-password`, admin, { password: 'OwnerB@456' });
      assert.equal(reset.status, 200, JSON.stringify(reset.body));
      assert.equal(reset.body.sessions_revoked, true);
      assert.equal((await request('GET', '/stock', shopB)).status, 401);
      shopB = await login('ownerB', 'OwnerB@456');
      assert.equal((await request('GET', '/stock', shopB)).status, 200);
    });
});
