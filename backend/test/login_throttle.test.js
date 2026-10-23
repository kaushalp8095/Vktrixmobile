// Login brute-force protection: galat password ke baad 429, sahi password se
// counter saaf, aur doosra username lock nahi hota.
//
// Limits chhoti rakhi gayi hain (3 attempts / 1.2s) taaki test jaldi chale.
process.env.AUTH_LOGIN_MAX = '3';
process.env.AUTH_LOGIN_WINDOW_MS = '1200';
process.env.AUTH_IP_MAX = '1000'; // per-IP counter is test me na aaye
process.env.RATE_LIMIT_MAX = '1000';
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'isolated-test-secret-never-use-in-production';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

process.env.DB_CLIENT = 'better-sqlite3';
process.env.SQLITE_FILE = process.env.TEST_SQLITE_FILE || path.join(os.tmpdir(), `vktrix-throttle-${process.pid}.sqlite`);
for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}

const db = require('../src/db');
const migrate = require('../src/migrate');
const { createApp } = require('../src/server');

let server;
let base;

async function request(method, route, data, token) {
  const response = await fetch(base + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(data === undefined ? {} : { body: JSON.stringify(data) }),
  });
  return { status: response.status, body: await response.json(), headers: response.headers };
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

test('login throttles after repeated failures and forgives a correct password', async t => {
  server = createApp().listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}/api`;
  t.after(async () => {
    if (server) await new Promise(resolve => server.close(resolve));
    await db.destroy();
    for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
  });
  await migrate();
  await db('users').whereNot({ username: 'superadmin' }).del();
  await db('shops').del();
  const admin = (await request('POST', '/auth/login',
    { username: 'superadmin', password: 'AuditOnly@123' })).body.token;
  const shop = await request('POST', '/admin/shops',
    { name: 'Throttle Mobile', username: 'throttle', password: 'Throttle@123' }, admin);
  assert.equal(shop.status, 200, JSON.stringify(shop.body));

  // 3 galat attempts allowed, 4th par 429 + Retry-After.
  for (let i = 0; i < 3; i++) {
    const r = await request('POST', '/auth/login', { username: 'throttle', password: 'wrong-password' });
    assert.equal(r.status, 401, `attempt ${i + 1} should be a normal 401`);
  }
  const blocked = await request('POST', '/auth/login', { username: 'throttle', password: 'wrong-password' });
  assert.equal(blocked.status, 429);
  assert.equal(blocked.body.code, 'login_rate_limited');
  assert.ok(Number(blocked.headers.get('retry-after')) >= 1);

  // Locked hone ke baad sahi password bhi nahi — warna limit ka koi matlab nahi.
  const locked = await request('POST', '/auth/login', { username: 'throttle', password: 'Throttle@123' });
  assert.equal(locked.status, 429);

  // Username case-insensitive hai, warna 'Throttle' se limit bypass ho jati.
  const upper = await request('POST', '/auth/login', { username: 'THROTTLE', password: 'wrong-password' });
  assert.equal(upper.status, 429);

  // Doosra username apna alag counter rakhta hai.
  const other = await request('POST', '/auth/login', { username: 'superadmin', password: 'AuditOnly@123' });
  assert.equal(other.status, 200, JSON.stringify(other.body));

  // Window khatam — phir se login ho jaata hai, aur success counter reset karta hai.
  await sleep(1300);
  const afterWindow = await request('POST', '/auth/login', { username: 'throttle', password: 'Throttle@123' });
  assert.equal(afterWindow.status, 200, JSON.stringify(afterWindow.body));
  for (let i = 0; i < 3; i++) {
    const r = await request('POST', '/auth/login', { username: 'throttle', password: 'wrong-password' });
    assert.equal(r.status, 401, 'successful login ne counter saaf kar diya');
  }
});
