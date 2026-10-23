// HTTP-layer security: CORS default off, no-store on customer data, body-size
// guard before JSON parsing, alg-pinned JWTs, aur 5xx par andar ki detail leak
// na hona. Ye sab wahi `createApp()` use karta hai jo production me chalta hai.
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'isolated-test-secret-never-use-in-production';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';
process.env.RATE_LIMIT_MAX = '100000';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const jwt = require('jsonwebtoken');

process.env.DB_CLIENT = 'better-sqlite3';
process.env.SQLITE_FILE = process.env.TEST_SQLITE_FILE || path.join(os.tmpdir(), `vktrix-httpsec-${process.pid}.sqlite`);
for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}

const db = require('../src/db');
const migrate = require('../src/migrate');
const { createApp } = require('../src/server');

let server;
let base;

async function withApp(t) {
  server = createApp().listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}/api`;
  t.after(async () => {
    await new Promise(resolve => server.close(resolve));
  });
}

async function request(method, route, { data, token, headers = {} } = {}) {
  const response = await fetch(base + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    ...(data === undefined ? {} : { body: typeof data === 'string' ? data : JSON.stringify(data) }),
  });
  const text = await response.text();
  let body = null;
  try { body = JSON.parse(text); } catch { body = text; }
  return { status: response.status, body, headers: response.headers };
}

test('production security middleware behaves as documented', async t => {
  await migrate();
  await withApp(t);

  // ---- CORS: default me koi ACAO header nahi (mobile app ko chahiye bhi nahi) ----
  const noCors = await request('GET', '/stock', { headers: { Origin: 'https://evil.example' } });
  assert.equal(noCors.headers.get('access-control-allow-origin'), null,
    'bina CORS_ORIGINS ke kisi bhi origin ko allow nahi karna chahiye');

  // ---- Standard hardening headers ----
  assert.equal(noCors.headers.get('x-powered-by'), null);
  assert.equal(noCors.headers.get('x-content-type-options'), 'nosniff');
  assert.ok(noCors.headers.get('strict-transport-security'), 'HSTS on');
  // ---- Customer data cache me nahi baithna chahiye ----
  assert.match(noCors.headers.get('cache-control') || '', /no-store/);

  // ---- Body-size guard: chhote route par 200 KB reject, photo route par allow ----
  const huge = JSON.stringify({ username: 'a'.repeat(150000), password: 'x' });
  const rejected = await request('POST', '/auth/login', { data: huge });
  assert.equal(rejected.status, 413);
  assert.equal(rejected.body.code, 'body_too_large');
  const allowed = await request('POST', '/buy', { data: huge });
  assert.equal(allowed.status, 401, 'photo route ko size guard nahi rokta (auth baad me hota hai)');

  // ---- JWT algorithm pin: same secret se HS384 token bhi reject ----
  const login = await request('POST', '/auth/login', { data: { username: 'superadmin', password: 'AuditOnly@123' } });
  assert.equal(login.status, 200, JSON.stringify(login.body));
  const payload = { id: 1, role: 'superadmin', shop_id: null, tv: 0 };
  const forged = jwt.sign(payload, process.env.JWT_SECRET, { algorithm: 'HS384', expiresIn: '1h' });
  const wrongAlg = await request('GET', '/stock', { token: forged });
  assert.equal(wrongAlg.status, 401, 'sirf HS256 tokens chalti hain');

  // Asli token HS256 hai aur chalta hai (superadmin ko shop data ke liye support
  // grant chahiye, isliye 403 — par 401 nahi, matlab token valid hai).
  const real = await request('GET', '/stock', { token: login.body.token });
  assert.equal(real.status, 403);
  assert.equal(real.body.code, 'support_access_required');
});

test('5xx par client ko internal error detail nahi milti', async t => {
  await withApp(t);
  await db.destroy(); // ab har query "Unable to acquire a connection" degi
  const r = await request('POST', '/auth/login', { data: { username: 'superadmin', password: 'AuditOnly@123' } });
  assert.equal(r.status, 500);
  assert.equal(r.body.error, 'Something went wrong on the server. Please try again.');
  assert.ok(!/connection|sqlite|select|knex/i.test(JSON.stringify(r.body)), 'DB/library detail leak nahi honi chahiye');
});

test('CORS_ORIGINS set ho to sirf wahi origin allowed', async t => {
  process.env.CORS_ORIGINS = 'https://admin.example.com';
  const app = createApp();
  const srv = app.listen(0, '127.0.0.1');
  await new Promise(resolve => srv.once('listening', resolve));
  const url = `http://127.0.0.1:${srv.address().port}/api/stock`;
  t.after(async () => { await new Promise(resolve => srv.close(resolve)); delete process.env.CORS_ORIGINS; });

  const good = await fetch(url, { headers: { Origin: 'https://admin.example.com' } });
  assert.equal(good.headers.get('access-control-allow-origin'), 'https://admin.example.com');
  const bad = await fetch(url, { headers: { Origin: 'https://evil.example' } });
  assert.equal(bad.headers.get('access-control-allow-origin'), null);
  // Mobile app Origin bhejti hi nahi — usse kabhi block nahi hona chahiye.
  const mobile = await fetch(url);
  assert.equal(mobile.status, 401, 'bina Origin wali request normal chalti hai');
});
