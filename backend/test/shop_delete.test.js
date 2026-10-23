// Shop delete ka contract: sirf **khaali** shop hard-delete hoti hai. Jisme
// stock, sales ya support-access ka itihaas hai wo 409 `shop_has_history` deti
// hai aur admin ko deactivate karna padta hai — shop owner ki books kabhi
// delete se na mitein.
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
  process.env.SQLITE_FILE = process.env.TEST_SQLITE_FILE || path.join(os.tmpdir(), `vktrix-shop-delete-${process.pid}.sqlite`);
  for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
}
process.env.JWT_SECRET = 'isolated-test-secret-never-use-in-production';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';

const express = require('express');
const db = require('../src/db');
const migrate = require('../src/migrate');

const imei = '490154203237518';
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

async function createShop(name, username) {
  const created = await request('POST', '/admin/shops', adminToken, { name, username, password: 'Shop@123456' });
  assert.equal(created.status, 200, JSON.stringify(created.body));
  return created.body.id;
}

const shopNamed = async (name, token) =>
  (await request('GET', '/admin/shops', token)).body.find(s => s.name === name);

let adminToken;

test('only an empty shop can be deleted; shops with history can only be deactivated', async t => {
  await migrate();
  await db('support_access').del();
  await db('sale_payments').del(); await db('sales').del(); await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del(); await db('shops').del();

  const app = express();
  app.use(express.json({ limit: '9mb' }));
  app.use('/api/auth', require('../src/routes/auth'));
  app.use('/api/admin', require('../src/routes/admin'));
  app.use('/api', require('../src/routes/shop'));
  app.use((err, req, res, next) => res.status(err.status || 500).json({ error: err.message, code: err.code }));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}/api`;
  t.after(async () => {
    await new Promise(resolve => server.close(resolve));
    await db.destroy();
    if (!process.env.TEST_DATABASE_URL)
      for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
  });

  const login = await request('POST', '/auth/login', null,
    { username: process.env.SUPERADMIN_USERNAME, password: process.env.SUPERADMIN_PASSWORD });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  adminToken = login.body.token;

  // ---- Khaali shop: delete allowed ----
  const emptyId = await createShop('Empty Shop', 'emptyshop');
  assert.equal((await shopNamed('Empty Shop', adminToken)).can_delete, true);
  const removed = await request('DELETE', `/admin/shops/${emptyId}`, adminToken);
  assert.equal(removed.status, 200, JSON.stringify(removed.body));
  assert.equal(await shopNamed('Empty Shop', adminToken), undefined);
  assert.equal((await request('DELETE', `/admin/shops/${emptyId}`, adminToken)).status, 404);

  // ---- Stock (phones row) hai: 409 + data safe ----
  const stockedId = await createShop('Stocked Shop', 'stockedshop');
  await db('phones').insert({ shop_id: stockedId, imei, buy_price: 12000, buy_date: '2026-09-28' });
  assert.equal((await shopNamed('Stocked Shop', adminToken)).can_delete, false);
  const blocked = await request('DELETE', `/admin/shops/${stockedId}`, adminToken);
  assert.equal(blocked.status, 409, JSON.stringify(blocked.body));
  assert.equal(blocked.body.code, 'shop_has_history');
  assert.match(blocked.body.error, /Deactivate/i);
  assert.equal((await db('phones').where({ shop_id: stockedId })).length, 1, 'stock must survive a blocked delete');
  assert.ok(await db('shops').where({ id: stockedId }).first(), 'shop must survive a blocked delete');
  // Deactivate hi ek hi raasta hai — aur wo chalta hai.
  assert.equal((await request('PUT', `/admin/shops/${stockedId}`, adminToken, { active: false })).status, 200);
  const after = await shopNamed('Stocked Shop', adminToken);
  assert.ok(!after.active, 'shop must be deactivated');
  assert.equal(after.can_delete, false);

  // ---- Sirf support-access log hai: delete nahi (audit trail evidence) ----
  const auditedId = await createShop('Audited Shop', 'auditedshop');
  const started = await request('POST', `/admin/shops/${auditedId}/support-access`, adminToken,
    { reason: 'Shop owner called: sale entry stuck in ledger', minutes: 30 });
  assert.equal(started.status, 201, JSON.stringify(started.body));
  assert.equal((await shopNamed('Audited Shop', adminToken)).can_delete, false);
  const blockedAudit = await request('DELETE', `/admin/shops/${auditedId}`, adminToken);
  assert.equal(blockedAudit.status, 409, JSON.stringify(blockedAudit.body));
  assert.equal((await db('support_access').where({ shop_id: auditedId })).length, 1);
});
