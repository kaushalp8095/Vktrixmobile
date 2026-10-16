// Super Admin ka shop data par access: default me kuch nahi, sirf temporary,
// reason-logged, read-only support session ke andar. Ye test wahi contract
// lock karta hai (screen par chhupana kaafi nahi — backend bhi rokta hai).
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
  process.env.SQLITE_FILE = process.env.TEST_SQLITE_FILE || path.join(os.tmpdir(), `vktrix-support-${process.pid}.sqlite`);
  for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
}
process.env.JWT_SECRET = 'isolated-test-secret-never-use-in-production';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';

const express = require('express');
const db = require('../src/db');
const migrate = require('../src/migrate');
const support = require('../src/support');

const imei = '490154203237518';
const buyDate = '2026-09-28';
const sellDate = '2026-09-29';
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

test('super admin needs reason-logged, read-only, time-boxed support access for shop data', async t => {
  await migrate();
  await db('support_access').del();
  await db('sale_payments').del(); await db('sales').del(); await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del(); await db('shops').del();
  await migrate(); // migration must stay idempotent

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

  const admin = await login('superadmin', 'AuditOnly@123');
  const created = await request('POST', '/admin/shops', admin, {
    name: 'Krishna Mobiles', owner_name: 'Krishna Patel', phone: '9876543210', address: 'Market Road',
    gst_no: '24ABCDE1234F1Z5', username: 'krishna', password: 'Krishna@123',
  });
  assert.equal(created.status, 200, JSON.stringify(created.body));
  const shopId = created.body.id;
  const owner = await login('krishna', 'Krishna@123');

  // Shop ka asli business data (buy + sell) — ye wo cheez hai jo admin ko default me nahi dikhni chahiye.
  const bought = await request('POST', '/buy', owner, {
    imei, brand: 'Apple', model: 'iPhone 13', ram: '4GB', storage: '128GB', condition: 'Good',
    buy_price: '31000', buy_date: buyDate, seller_name: 'Ramesh', seller_phone: '9876500000',
    seller_id_type: 'Aadhaar', seller_id_no: '1234 5678 9012', notes: 'INTERNAL NOTE',
  });
  assert.equal(bought.status, 200, JSON.stringify(bought.body));
  const phoneId = bought.body.id;
  const sold = await request('POST', '/sell', owner, {
    phone_id: phoneId, sell_price: '34000', sell_date: sellDate, customer_name: 'Meena',
    customer_phone: '9876500001', payment_mode: 'cash', amount_received: '20000',
  });
  assert.equal(sold.status, 200, JSON.stringify(sold.body));

  await t.test('masked contact: shop list hides contact and every business number', async () => {
    const r = await request('GET', '/admin/shops', admin);
    assert.equal(r.status, 200);
    const shop = r.body.find(s => s.id === shopId);
    assert.equal(shop.phone, undefined, 'full phone number must never be in the list payload');
    assert.equal(shop.phone_masked, '98•••••210');
    assert.equal(shop.has_phone, true);
    assert.equal(shop.stock_count, undefined, 'stock count is shop business data');
    assert.equal(shop.login.username, 'krishna');
    assert.equal(shop.support, null);
    assert.equal(shop.support_sessions, 0);
    assert.equal(support.maskPhone('98765'), '9••65');
    assert.equal(support.maskPhone(''), null);

    const dash = await request('GET', '/admin/dashboard', admin);
    assert.equal(dash.status, 200);
    assert.deepEqual(Object.keys(dash.body).sort(), ['active_shops', 'inactive_shops', 'shops', 'support_active']);
    assert.equal(dash.body.shops, 1);
    assert.equal(dash.body.active_shops, 1);
    assert.equal(dash.body.support_active, 0);
  });

  await t.test('without a support session the super admin gets 403 on every shop data route', async () => {
    const routes = ['/stock', '/sales', '/ledger', '/reports/summary', '/reports/daily',
      `/phones/${phoneId}`, `/receipts/sale/${sold.body.id}`, `/sales/${sold.body.id}/payments`];
    for (const route of routes) {
      const r = await request('GET', `${route}?shop_id=${shopId}`, admin);
      assert.equal(r.status, 403, `${route} -> ${r.status} ${JSON.stringify(r.body)}`);
      assert.equal(r.body.code, 'support_access_required');
    }
    // shop_id ke bina bhi kuch nahi
    assert.equal((await request('GET', '/stock', admin)).status, 403);
    // aur masked contact bhi band rehta hai
    const reveal = await request('POST', `/admin/shops/${shopId}/reveal-contact`, admin, {});
    assert.equal(reveal.status, 403);
    assert.equal(reveal.body.code, 'support_access_required');
  });

  let sessionId;
  await t.test('a support session needs a real reason and a sane time limit', async () => {
    const shortReason = await request('POST', `/admin/shops/${shopId}/support-access`, admin, { reason: 'check', minutes: 30 });
    assert.equal(shortReason.status, 400);
    const tooLong = await request('POST', `/admin/shops/${shopId}/support-access`, admin, { reason: 'Shop called about a stuck sale', minutes: 9999 });
    assert.equal(tooLong.status, 400);
    const started = await request('POST', `/admin/shops/${shopId}/support-access`, admin,
      { reason: 'Shop owner called: sale stuck in ledger, need to check the entry', minutes: 15 });
    assert.equal(started.status, 201, JSON.stringify(started.body));
    assert.equal(started.body.session.status, 'active');
    assert.equal(started.body.session.minutes, 15);
    assert.ok(started.body.session.expires_in_ms > 0 && started.body.session.expires_in_ms <= 15 * 60 * 1000);
    assert.equal(started.body.session.reads, 0);
    sessionId = started.body.session.id;

    const again = await request('POST', `/admin/shops/${shopId}/support-access`, admin,
      { reason: 'Second session while one is running', minutes: 15 });
    assert.equal(again.status, 409);

    const list = await request('GET', `/admin/shops?`, admin);
    const shop = list.body.find(s => s.id === shopId);
    assert.equal(shop.support.reason.startsWith('Shop owner called'), true);
    assert.ok(shop.support.expires_in_ms > 0);
    assert.equal(shop.support_sessions, 1);
  });

  await t.test('with an active session the admin can read (and every read is logged)', async () => {
    const stock = await request('GET', `/stock?shop_id=${shopId}`, admin);
    assert.equal(stock.status, 200, JSON.stringify(stock.body));
    assert.equal(stock.body.length, 0, 'the phone is sold, so stock is empty');
    const sales = await request('GET', `/sales?shop_id=${shopId}`, admin);
    assert.equal(sales.status, 200);
    assert.equal(sales.body.length, 1);
    assert.equal(sales.body[0].imei, imei);

    const log = await request('GET', `/admin/support-access?shop_id=${shopId}`, admin);
    assert.equal(log.status, 200);
    assert.equal(log.body.items.length, 1);
    assert.equal(log.body.items[0].id, sessionId);
    assert.equal(log.body.items[0].status, 'active');
    assert.ok(log.body.items[0].reads >= 1);
    assert.ok(log.body.items[0].last_read_ms > 0);
    assert.equal(log.body.items[0].shop_name, 'Krishna Mobiles');
  });

  await t.test('support access is read-only: no buy, sell, payment, edit or cancel', async () => {
    const attempts = [
      ['POST', '/buy', { shop_id: shopId, imei: '353328110000005', brand: 'Redmi', model: 'Note 12',
        condition: 'Good', buy_price: '100', buy_date: buyDate }],
      ['PUT', `/phones/${phoneId}`, { shop_id: shopId, notes: 'admin edit' }],
      ['DELETE', `/phones/${phoneId}`, { shop_id: shopId }],
      ['POST', '/sell', { shop_id: shopId, phone_id: phoneId, sell_price: '1', sell_date: sellDate }],
      ['POST', `/sales/${sold.body.id}/payments`, { shop_id: shopId, amount: '100', payment_date: sellDate }],
      ['DELETE', `/sales/${sold.body.id}`, { shop_id: shopId }],
    ];
    for (const [method, route, body] of attempts) {
      const r = await request(method, route, admin, body);
      assert.equal(r.status, 403, `${method} ${route} -> ${r.status} ${JSON.stringify(r.body)}`);
      assert.equal(r.body.code, 'support_access_read_only');
    }
    const untouched = await db('phones').where({ id: phoneId }).first();
    assert.equal(untouched.notes, 'INTERNAL NOTE');
    assert.equal(untouched.status, 'sold');
  });

  await t.test('revealing the masked contact needs the session too, and it is logged', async () => {
    const reveal = await request('POST', `/admin/shops/${shopId}/reveal-contact`, admin, {});
    assert.equal(reveal.status, 200);
    assert.equal(reveal.body.phone, '9876543210');
    assert.equal(reveal.body.contact_reveals, 1);
    const log = await request('GET', `/admin/support-access?shop_id=${shopId}`, admin);
    assert.equal(log.body.items[0].contact_reveals, 1);
    assert.ok(log.body.items[0].last_reveal_ms > 0);
  });

  await t.test('the shop owner sees the same log, and only for their own shop', async () => {
    const other = await request('POST', '/admin/shops', admin, { name: 'Om Communication', username: 'omcomm', password: 'Om@123456' });
    assert.equal(other.status, 200);
    const ownerLog = await request('GET', '/support-access', owner);
    assert.equal(ownerLog.status, 200, JSON.stringify(ownerLog.body));
    assert.equal(ownerLog.body.items.length, 1);
    const entry = ownerLog.body.items[0];
    assert.match(entry.reason, /sale stuck in ledger/);
    assert.equal(entry.admin_name, 'Super Admin');
    assert.ok(entry.reads >= 1);
    assert.equal(entry.contact_reveals, 1);
    assert.equal(entry.status, 'active');
    assert.ok(ownerLog.body.active.id === sessionId);

    // Doosri shop ka log is shop ko nahi dikhta (shop_id query ignore hoti hai).
    const forged = await request('GET', `/support-access?shop_id=${other.body.id}`, owner);
    assert.equal(forged.status, 200);
    assert.equal(forged.body.items.length, 1, 'still only its own single session');
    assert.equal(forged.body.items[0].shop_id, shopId);
  });

  await t.test('ending the session (admin ya shop) turant access band kar deta hai', async () => {
    const ended = await request('DELETE', `/admin/shops/${shopId}/support-access`, admin);
    assert.equal(ended.status, 200);
    assert.equal((await request('GET', `/stock?shop_id=${shopId}`, admin)).status, 403);
    const log = await request('GET', `/admin/support-access?shop_id=${shopId}`, admin);
    assert.equal(log.body.items[0].status, 'ended');
    assert.equal(log.body.items[0].end_reason, 'admin_ended');
    assert.equal((await request('GET', '/admin/shops', admin)).body.find(s => s.id === shopId).support, null);
  });

  await t.test('an expired session stops working on its own and shows up as expired', async () => {
    const started = await request('POST', `/admin/shops/${shopId}/support-access`, admin,
      { reason: 'Follow up on the same ledger question', minutes: 5 });
    assert.equal(started.status, 201);
    const id = started.body.session.id;
    assert.equal((await request('GET', `/stock?shop_id=${shopId}`, admin)).status, 200);
    // Session ko past me shift kar dein: waqt khatam hone par access bhi khatam.
    await db('support_access').where({ id }).update({ expires_at_ms: Date.now() - 1000 });
    assert.equal((await request('GET', `/stock?shop_id=${shopId}`, admin)).status, 403);
    const log = await request('GET', `/admin/support-access?shop_id=${shopId}`, admin);
    const entry = log.body.items.find(i => i.id === id);
    assert.equal(entry.status, 'expired');
    assert.equal(entry.end_reason, 'expired');
    // Aur is expired session ke saath contact bhi reveal nahi hota.
    assert.equal((await request('POST', `/admin/shops/${shopId}/reveal-contact`, admin, {})).status, 403);
  });

  await t.test('another super admin / another shop ke liye session kaam nahi karta', async () => {
    const otherShop = await db('shops').where({ name: 'Om Communication' }).first();
    const started = await request('POST', `/admin/shops/${otherShop.id}/support-access`, admin,
      { reason: 'Checking Om Communication activation issue', minutes: 5 });
    assert.equal(started.status, 201);
    // Session sirf usi shop ke liye hai.
    assert.equal((await request('GET', `/stock?shop_id=${otherShop.id}`, admin)).status, 200);
    assert.equal((await request('GET', `/stock?shop_id=${shopId}`, admin)).status, 403);
    // Unknown shop id pe kuch nahi.
    assert.equal((await request('GET', '/stock?shop_id=9999', admin)).status, 403);
    assert.equal((await request('GET', '/stock?shop_id=1 OR 1=1', admin)).status, 400);
  });
});
