// Dashboard ka "Credit / pending payments" card ALL-TIME dues dikhaye aur ledger
// screen se kabhi alag na ho.
//
// Bug tha: card /reports/summary ke `receivables` par chalta tha, jo period
// scoped hai — bina from/to bheje backend default [today, today] use karta hai.
// Isliye kal (ya usse purani) sale ka balance ledger me "1 pending" dikhta tha,
// par dashboard card par "All payments are clear" / CLEAR chip.
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
  process.env.SQLITE_FILE = path.join(os.tmpdir(), `vktrix-dues-${process.pid}.sqlite`);
  for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
}
process.env.JWT_SECRET = 'isolated-dues-tests';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';

const express = require('express');
const db = require('../src/db');
const migrate = require('../src/migrate');

function withCheckDigit(fourteen) {
  let sum = 0;
  for (let i = 0; i < 14; i++) {
    let d = +fourteen[i];
    if (i % 2 === 1) { d *= 2; if (d > 9) d -= 9; }
    sum += d;
  }
  return fourteen + String((10 - sum % 10) % 10);
}
const IMEI = withCheckDigit('35332811900003');

/// Server timezone se pehle bhi safe: date string hisaab se banao.
const daysAgo = n => new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);
const today = () => daysAgo(0);

let server, base;
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
  return r;
}

// Ek hi server/db lifecycle: doosre test me knex ko destroy karke dobara use
// nahi kiya ja sakta, isliye subtests share karte hain.
test('dashboard dues', async t => {
  await migrate();
  await db('sale_payments').del(); await db('sales').del(); await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del(); await db('shops').del();

  const app = express();
  app.use(express.json({ limit: '9mb' }));
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
    if (!process.env.TEST_DATABASE_URL)
      for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
  });

  const admin = (await login('superadmin', 'AuditOnly@123')).body.token;

  await t.test('are all-time and always agree with the ledger', async () => {
  const shop = await request('POST', '/admin/shops', admin,
    { name: 'Dues Mobiles', username: 'dues', password: 'Dues@123' });
  assert.equal(shop.status, 200, JSON.stringify(shop.body));
  const token = (await login('dues', 'Dues@123')).body.token;

  // 30 din purani sale jiska balance baaki hai — dashboard card ke liye ye
  // dikhna zaroori hai, warna shop owner sochta hai ki sab clear hai.
  const bought = await request('POST', '/buy', token, {
    imei: IMEI, brand: 'Samsung', model: 'Galaxy S23', ram: '8GB', storage: '256GB', color: 'Black',
    condition: 'Good', buy_price: '20000', buy_date: daysAgo(40), seller_name: 'Phone Seller',
  });
  assert.equal(bought.status, 200, JSON.stringify(bought.body));
  const sold = await request('POST', '/sell', token, {
    phone_id: bought.body.id, sell_price: '26000', sell_date: daysAgo(30),
    customer_name: 'Old Credit', customer_phone: '9988776655', payment_mode: 'cash',
    amount_received: '10000',
  });
  assert.equal(sold.status, 200, JSON.stringify(sold.body));
  assert.equal(sold.body.balance_due, 16000);

  // Card ka naya source: all-time dues.
  const dues = await request('GET', '/ledger/summary', token);
  assert.equal(dues.status, 200, JSON.stringify(dues.body));
  assert.equal(dues.body.pending_count, 1);
  assert.equal(dues.body.outstanding, 16000);

  // Ledger screen jo dikhata hai (default status=pending) bilkul wahi number.
  const ledger = await request('GET', '/ledger', token);
  assert.equal(ledger.status, 200);
  assert.deepEqual(ledger.body.summary, dues.body,
    'dashboard aur ledger ka summary ek hi hisaab se bane');

  // Yahi wo bug tha: /reports/summary bina from/to → sirf aaj ki sales, isliye
  // period-scoped receivables clear dikhata hai. Card ise use nahi karta.
  const report = await request('GET', '/reports/summary', token);
  assert.equal(report.status, 200, JSON.stringify(report.body));
  assert.equal(report.body.receivables.pending_count, 0);
  assert.equal(report.body.receivables.outstanding, 0);

  // Balance aane ke baad dono jagah clear.
  const paid = await request('POST', `/sales/${sold.body.id}/payments`, token,
    { amount: '16000', payment_date: today(), payment_mode: 'cash' });
  assert.equal(paid.status, 200, JSON.stringify(paid.body));
  assert.equal(paid.body.balance_due, 0);

  const cleared = await request('GET', '/ledger/summary', token);
  assert.equal(cleared.body.pending_count, 0);
  assert.equal(cleared.body.outstanding, 0);
  assert.deepEqual((await request('GET', '/ledger', token)).body.summary, cleared.body);
  });

  await t.test('stay shop-scoped and refuse support-mode reads', async () => {
  await request('POST', '/admin/shops', admin, { name: 'Alpha Dues', username: 'alpha2', password: 'Alpha@123' });
  await request('POST', '/admin/shops', admin, { name: 'Beta Dues', username: 'beta2', password: 'Beta@123' });
  const alphaToken = (await login('alpha2', 'Alpha@123')).body.token;
  const betaToken = (await login('beta2', 'Beta@123')).body.token;

  // Dusre shop ka udhaar kabhi leak na ho.
  const betaDues = await request('GET', '/ledger/summary', betaToken);
  assert.equal(betaDues.status, 200);
  assert.equal(betaDues.body.pending_count, 0);
  assert.equal(betaDues.body.outstanding, 0);

  // Super admin bina support session ke shop data na dekhe (jaise /ledger).
  const asAdmin = await request('GET', '/ledger/summary', admin);
  assert.equal(asAdmin.status, 403);
  assert.equal(asAdmin.body.code, 'support_access_required');
  });
});
