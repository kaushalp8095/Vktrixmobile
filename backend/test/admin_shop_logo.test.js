// Shop ka bill logo: list me sirf `has_logo` flag jaata hai (base64 nahi), aur
// admin "Edit details" kholne par `GET /admin/shops/:id/logo` se poora logo
// laata hai — isse pata chalta hai ki kaunsa logo upload hua hai.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

process.env.AUTH_LOGIN_MAX = '50';   // is test me throttle ki zaroorat nahi
process.env.AUTH_IP_MAX = '1000';
process.env.RATE_LIMIT_MAX = '1000';
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'isolated-test-secret-never-use-in-production';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';

process.env.DB_CLIENT = 'better-sqlite3';
process.env.SQLITE_FILE = process.env.TEST_SQLITE_FILE || path.join(os.tmpdir(), `vktrix-shop-logo-${process.pid}.sqlite`);
for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}

const db = require('../src/db');
const migrate = require('../src/migrate');
const { createApp } = require('../src/server');

// 1x1 PNG — data URL schema aur size limit ke liye kaafi.
const LOGO = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const LOGO2 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

let server;
let base;

async function request(method, route, data, token) {
  const response = await fetch(base + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(data === undefined ? {} : { body: JSON.stringify(data) }),
  });
  return { status: response.status, body: await response.json() };
}

test('bill logo: list sirf flag bhejti hai, preview endpoint poora logo deta hai', async t => {
  server = createApp().listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}/api`;
  t.after(async () => {
    if (server) await new Promise(resolve => server.close(resolve));
    await db.destroy();
    for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
  });

  await migrate();
  await db('support_access').del();
  await db('sale_payments').del(); await db('sales').del(); await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del(); await db('shops').del();

  const login = await request('POST', '/auth/login',
    { username: 'superadmin', password: 'AuditOnly@123' });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  const admin = login.body.token;

  const created = await request('POST', '/admin/shops', {
    name: 'Logo Mobile', username: 'logomobile', password: 'Logo@12345',
  }, admin);
  assert.equal(created.status, 200, JSON.stringify(created.body));
  const shopId = created.body.id;

  const rowFor = async () => (await request('GET', '/admin/shops', undefined, admin)).body
    .find(s => s.id === shopId);
  const logoFor = async (id = shopId, token = admin) =>
    request('GET', `/admin/shops/${id}/logo`, undefined, token);

  // ---- Naya shop: logo nahi ----
  const empty = await rowFor();
  assert.equal(empty.has_logo, false);
  assert.equal('logo_data' in empty, false, 'list me base64 logo kabhi nahi jaata');
  assert.equal((await logoFor()).status, 200);
  assert.equal((await logoFor()).body.logo_data, null);

  // ---- Logo upload (PUT) ----
  const saved = await request('PUT', `/admin/shops/${shopId}`, { logo_data: LOGO }, admin);
  assert.equal(saved.status, 200, JSON.stringify(saved.body));

  const withLogo = await rowFor();
  assert.equal(withLogo.has_logo, true, 'Edit dialog ko pata hona chahiye ki logo hai');
  assert.equal('logo_data' in withLogo, false, 'list halki rehni chahiye');
  const preview = await logoFor();
  assert.equal(preview.status, 200);
  assert.equal(preview.body.logo_data, LOGO, 'wahi logo wapas milna chahiye jo upload hua');

  // Badla hua logo bhi turant dikhe (admin ko "konsa logo" ka jawab milta rahe).
  await request('PUT', `/admin/shops/${shopId}`, { logo_data: LOGO2 }, admin);
  assert.equal((await logoFor()).body.logo_data, LOGO2);

  // ---- Logo hatana: PUT me khaali string ----
  await request('PUT', `/admin/shops/${shopId}`, { logo_data: '' }, admin);
  assert.equal((await rowFor()).has_logo, false);
  assert.equal((await logoFor()).body.logo_data, null);

  // ---- Sirf super admin ----
  const shopLogin = await request('POST', '/auth/login', { username: 'logomobile', password: 'Logo@12345' });
  assert.equal(shopLogin.status, 200, JSON.stringify(shopLogin.body));
  const asShop = await logoFor(shopId, shopLogin.body.token);
  assert.equal(asShop.status, 403, 'shop owner doosri shop ka admin data na dekhe');

  // ---- Unknown shop ----
  assert.equal((await logoFor(999999)).status, 404);
});
