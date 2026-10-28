// Shop ka bill logo:
//   * upload par **auto-adjust** — margin trim + centre + 512px square tile, taaki
//     logo PDF/Profile/list teeno me ek jaisa "set" dikhe (koi bhi shape ho)
//   * list me sirf `has_logo` + 128px square `logo_thumb` jaata hai (poora base64 kabhi nahi)
//   * `GET /admin/shops/:id/logo` poora (auto-adjusted) logo deta hai
//   * logo badalne/hatane par thumbnail bhi turant update hota hai
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const jpeg = require('jpeg-js');

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

/// 480x240 JPEG — asli logo jaisa (app bhi JPEG hi bhejti hai): safed page par
/// beech me brand ka block, kinare par margin — trim/auto-adjust ka asli case.
function makeJpeg(width = 480, height = 240, shade = 1) {
  const data = Buffer.alloc(width * height * 4, 255);
  const x0 = Math.round(width * 0.12), x1 = Math.round(width * 0.88);
  const y0 = Math.round(height * 0.10), y1 = Math.round(height * 0.90);
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const i = (y * width + x) * 4;
      data[i] = (x * shade) % 256;
      data[i + 1] = (y * 2) % 256;
      data[i + 2] = shade === 1 ? 140 : 60;
      data[i + 3] = 255;
    }
  }
  return 'data:image/jpeg;base64,' + jpeg.encode({ data, width, height }, 85).data.toString('base64');
}

const LOGO = makeJpeg(480, 240, 1);
const LOGO2 = makeJpeg(200, 200, 3);
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

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

const decodeDataUrl = url => jpeg.decode(Buffer.from(String(url).split(',')[1], 'base64'), { useTArray: true });

const pixel = (d, x, y) => { const i = (y * d.width + x) * 4; return [d.data[i], d.data[i + 1], d.data[i + 2]]; };
const white = ([r, g, b]) => r > 240 && g > 240 && b > 240;
const dimsOf = url => { const d = decodeDataUrl(url); return { width: d.width, height: d.height }; };
/// Tile me non-white content ka bounding box — auto-adjust ne kitni jagah bhari,
/// ye batata hai (16px inset chhod kar, kyunki edge par JPEG ringing ho sakti hai).
function contentBox(url) {
  const d = decodeDataUrl(url);
  let minX = d.width, minY = d.height, maxX = -1, maxY = -1;
  for (let y = 16; y < d.height - 16; y++) {
    for (let x = 16; x < d.width - 16; x++) {
      if (white(pixel(d, x, y))) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  return maxX < 0 ? null : { width: maxX - minX + 1, height: maxY - minY + 1, size: d.width };
}

test('bill logo: list sirf thumbnail bhejti hai, preview endpoint poora logo deta hai', async t => {
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
  assert.equal(empty.logo_thumb, null);
  assert.equal('logo_data' in empty, false, 'list me base64 logo kabhi nahi jaata');
  assert.equal((await logoFor()).status, 200);
  assert.equal((await logoFor()).body.logo_data, null);

  // ---- Logo upload (PUT) ----
  const saved = await request('PUT', `/admin/shops/${shopId}`, { logo_data: LOGO }, admin);
  assert.equal(saved.status, 200, JSON.stringify(saved.body));

  const withLogo = await rowFor();
  assert.equal(withLogo.has_logo, true, 'Edit dialog ko pata hona chahiye ki logo hai');
  assert.equal('logo_data' in withLogo, false, 'list halki rehni chahiye');

  // Thumbnail: **full-bleed** square JPEG 128 (list me 44-56dp box ke liye),
  // chhota — tile me koi padding/patti nahi, isliye box poora bhara dikhta hai.
  assert.match(String(withLogo.logo_thumb), /^data:image\/jpeg;base64,/);
  assert.ok(withLogo.logo_thumb.length < 33 * 1024, `thumb too big: ${withLogo.logo_thumb.length}`);
  assert.deepEqual(dimsOf(withLogo.logo_thumb), { width: 128, height: 128 });

  // ---- Auto-adjust: 480x240 (wide) image bhi 512x512 square tile ----
  const preview = await logoFor();
  assert.equal(preview.status, 200);
  const savedLogo = preview.body.logo_data;
  assert.notEqual(savedLogo, LOGO, 'server logo ko auto-adjust karta hai');
  const logo = decodeDataUrl(savedLogo);
  assert.deepEqual({ width: logo.width, height: logo.height }, { width: 512, height: 512 });
  // Full-bleed: tile ka **poora** area content hai — na upar/neeche patti, na
  // kinare par safed padding. (Purane "fit" tile me wide logo ke saath safed
  // letterbox hota tha, wahi box me khaali jagah jaisa dikhta tha.)
  const box = contentBox(savedLogo);
  assert.ok(box, 'content mile');
  // contentBox 16px inset chhod kar naapta hai (JPEG ringing), isliye poora
  // bharne ka matlab hai 512 − 2×16 tak pahunchna.
  assert.ok(Math.max(box.width, box.height) >= 512 - 2 * 16,
    `content poora tile bhare: ${box.width}x${box.height}`);
  for (const [x, y] of [[2, 2], [509, 2], [2, 509], [509, 509]]) {
    assert.equal(white(pixel(logo, x, y)), false, `corner ${x},${y} par content ho (patti nahi)`);
  }

  // ---- Wahi logo dobara bhejna (idempotent): dobara recompress nahi ----
  await request('PUT', `/admin/shops/${shopId}`, { logo_data: savedLogo }, admin);
  assert.equal((await logoFor()).body.logo_data, savedLogo, 'normalized logo dobara nahi badalta');

  // ---- Badla hua logo: thumbnail bhi naya ----
  const firstThumb = withLogo.logo_thumb;
  await request('PUT', `/admin/shops/${shopId}`, { logo_data: LOGO2 }, admin);
  const swapped = await rowFor();
  assert.notEqual((await logoFor()).body.logo_data, savedLogo, 'naya logo save hua');
  assert.notEqual(swapped.logo_thumb, firstThumb, 'purana thumbnail nahi dikhna chahiye');
  assert.deepEqual(dimsOf(swapped.logo_thumb), { width: 128, height: 128 });

  // ---- Baaki fields edit karna thumbnail ko chhedta nahi ----
  await request('PUT', `/admin/shops/${shopId}`, { address: 'MG Road' }, admin);
  assert.equal((await rowFor()).logo_thumb, swapped.logo_thumb);

  // ---- Logo hatana: thumbnail bhi saaf ----
  await request('PUT', `/admin/shops/${shopId}`, { logo_data: '' }, admin);
  const cleared = await rowFor();
  assert.equal(cleared.has_logo, false);
  assert.equal(cleared.logo_thumb, null);
  assert.equal((await logoFor()).body.logo_data, null);

  // ---- PNG logo (thumbnail nahi ban sakta): logo rehta hai, row icon dikhati hai ----
  await request('PUT', `/admin/shops/${shopId}`, { logo_data: PNG }, admin);
  const png = await rowFor();
  assert.equal(png.has_logo, true);
  assert.equal(png.logo_thumb, null, 'PNG ka thumb nahi — list icon dikhayegi');
  assert.equal((await logoFor()).body.logo_data, PNG);

  // ---- Purane (pre-auto-adjust) logos ka backfill (migration) ----
  // One-time backfill meta flag se chalta hai; test me flag hata kar dobara
  // chalate hain (asli deployment par ye sirf ek baar hota hai).
  await db('shops').where({ id: shopId }).update({ logo_data: LOGO, logo_thumb: null });
  await db('meta').where({ key: 'logo_full_bleed_v1' }).del();
  await migrate();
  const backfilled = await db('shops').where({ id: shopId }).first('logo_data', 'logo_thumb');
  assert.match(String(backfilled.logo_thumb), /^data:image\/jpeg;base64,/);
  assert.deepEqual(dimsOf(backfilled.logo_thumb), { width: 128, height: 128 });
  assert.deepEqual(dimsOf(backfilled.logo_data), { width: 512, height: 512 },
    'purana logo bhi naye full-bleed tile me aa jata hai');

  // Purana letterbox thumbnail/crop boot par ek hi baar force-crop hota hai.
  const staleThumb = 'data:image/jpeg;base64,/9j/4AAQSkZJRg==';
  await db('shops').where({ id: shopId }).update({ logo_thumb: staleThumb });
  await db('meta').where({ key: 'logo_full_bleed_v1' }).del();
  await migrate();
  const upgraded = await db('shops').where({ id: shopId }).first('logo_data', 'logo_thumb');
  assert.notEqual(upgraded.logo_thumb, staleThumb, 'purana thumbnail upgrade hua');
  assert.deepEqual(dimsOf(upgraded.logo_thumb), { width: 128, height: 128 });

  // Flag lagne ke baad har boot par dobara process nahi hota.
  const before = await db('shops').where({ id: shopId }).first('logo_data', 'logo_thumb');
  await migrate();
  const after = await db('shops').where({ id: shopId }).first('logo_data', 'logo_thumb');
  assert.deepEqual(after, before, 'backfill ek hi baar chalta hai');

  // ---- Sirf super admin ----
  const shopLogin = await request('POST', '/auth/login', { username: 'logomobile', password: 'Logo@12345' });
  assert.equal(shopLogin.status, 200, JSON.stringify(shopLogin.body));
  const asShop = await logoFor(shopId, shopLogin.body.token);
  assert.equal(asShop.status, 403, 'shop owner doosri shop ka admin data na dekhe');

  // ---- Unknown shop ----
  assert.equal((await logoFor(999999)).status, 404);
});
