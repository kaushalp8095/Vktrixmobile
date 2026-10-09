// Buy form additions: serial number, ID proof photo, "Visiting Card" proof type
// and the RAM/storage/colour dropdown built from the app's own data.
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
  process.env.SQLITE_FILE = path.join(os.tmpdir(), `vktrix-buy-${process.pid}.sqlite`);
  for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
}
process.env.JWT_SECRET = 'isolated-test-secret-never-use-in-production';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';

const express = require('express');
const db = require('../src/db');
const migrate = require('../src/migrate');
const V = require('../src/validation');
const { validImei } = require('../src/util');
const suggestions = require('../src/suggestions');
const tacApi = require('../src/tacApi');

// 1x1 transparent PNG, as the app would send it.
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';

// Appends a Luhn check digit so test IMEIs are genuinely valid.
function withCheckDigit(fourteen) {
  let sum = 0;
  for (let i = 0; i < 14; i++) {
    let d = +fourteen[i];
    if (i % 2 === 1) { d *= 2; if (d > 9) d -= 9; }
    sum += d;
  }
  return fourteen + String((10 - (sum % 10)) % 10);
}
const IMEI_A = withCheckDigit('35332811123456'); // TAC 35332811 (seeded iPhone 13)
const IMEI_B = withCheckDigit('35332811123457');
assert.ok(validImei(IMEI_A) && validImei(IMEI_B) && IMEI_A !== IMEI_B);

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
  return r.body.token;
}

test('idPhoto accepts image data URLs and rejects everything else', () => {
  assert.equal(V.idPhoto(null), null);
  assert.equal(V.idPhoto(''), null);
  assert.equal(V.idPhoto(PNG), PNG);
  assert.match(V.idPhoto('data:image/jpeg;base64,AAAA'), /^data:image\/jpeg/);
  assert.match(V.idPhoto('data:image/webp;base64,AAAA'), /^data:image\/webp/);

  for (const bad of [
    'https://example.com/a.png',                  // not a data URL
    'data:text/plain;base64,SGVsbG8=',            // not an image
    'data:image/png;base64',                      // missing payload
    'data:image/svg+xml;base64,AAAA',             // SVG can carry scripts
    'data:image/png;base64,!!!not base64!!!',
    'data:image/png;base64,' + 'A'.repeat(64) + ' ',
  ]) {
    assert.throws(() => V.idPhoto(bad), /must be a JPEG, PNG or WebP data URL/, `should reject: ${bad.slice(0, 40)}`);
  }
  // Oversized payloads are rejected on length, before the regex runs.
  const huge = 'data:image/png;base64,' + 'A'.repeat(V.ID_PHOTO_MAX_BYTES * 2);
  assert.throws(() => V.idPhoto(huge), /too large/);
  assert.throws(() => V.idPhoto(42), /must be a data URL/);
});

test('ID proof types now include Visiting Card', () => {
  assert.ok(V.ID_TYPES.includes('Visiting Card'));
  for (const t of ['Aadhaar', 'PAN', 'Voter ID', 'Driving Licence', 'Visiting Card']) {
    const out = V.phoneData({ seller_id_type: t }, true);
    assert.equal(out.seller_id_type, t);
  }
  assert.throws(() => V.phoneData({ seller_id_type: 'Ration Card' }, true), /seller_id_type invalid/);
  assert.throws(() => V.phoneData({ seller_id_type: 'visiting card' }, true), /seller_id_type invalid/);
});

test('serial_number is optional and length-capped', () => {
  assert.equal(V.phoneData({ serial_number: '  F2LV9K1ZQ1YH ' }, true).serial_number, 'F2LV9K1ZQ1YH');
  assert.equal(V.phoneData({ serial_number: null }, true).serial_number, null);
  assert.equal('serial_number' in V.phoneData({ model: 'X' }, true), false, 'partial updates leave it untouched');
  assert.throws(() => V.phoneData({ serial_number: 'x'.repeat(65) }, true), /too long/);
});

test('suggestion lists are built from this app\'s own data, exact match first', async () => {
  await migrate();
  await db('tac_models').whereIn('tac', ['35000001', '35000002', '35000003', '35000004', '35000005']).del();
  const rows = [
    ['35000001', 'Samsung', 'Galaxy A51', '6GB', '128GB', 'Black'],
    ['35000002', 'Samsung', 'Galaxy A51', '8GB', '256GB', 'Blue'],
    ['35000003', 'Samsung', 'Galaxy S21', '8GB', '128GB', 'Grey'],
    ['35000004', 'Apple', 'iPhone 13', '4GB', '64GB', 'White'],
    ['35000005', 'Samsung', 'Galaxy A51', '8gb', '128GB', 'black'], // other casing -> de-duplicated
  ];
  await db('tac_models').insert(rows.map(([tac, brand, model, ram, storage, color]) =>
    ({ tac, brand, model, ram, storage, color, source: 'learned' })));

  const exact = await db('tac_models').where({ tac: '35000001' }).first();
  const o = await suggestions.options(exact);

  // Stored value for this exact TAC first, then other variants of the same
  // model, then the same brand, then the static fallback.
  assert.deepEqual(o.ram, ['6GB', '8GB', '2GB', '3GB', '4GB', '12GB', '16GB']);
  assert.deepEqual(o.storage, ['128GB', '256GB', '16GB', '32GB', '64GB', '512GB', '1TB']);
  assert.deepEqual(o.color, ['Black', 'Blue', 'Grey', 'White', 'Silver', 'Gold', 'Green', 'Purple', 'Red']);

  // No match at all: fallbacks only, so the dropdown is never empty.
  assert.deepEqual(await suggestions.options(null), {
    ram: suggestions.FALLBACK.ram,
    storage: suggestions.FALLBACK.storage,
    color: suggestions.FALLBACK.color,
  });

  // A different TAC of the same model still leads with its own value.
  const other = await db('tac_models').where({ tac: '35000002' }).first();
  assert.equal((await suggestions.options(other)).ram[0], '8GB');

  // Brand scoping works and never mixes brands into the same-model query.
  assert.deepEqual(await suggestions.distinctBy('ram', { brand: 'Apple' }), ['4GB']);
  assert.deepEqual(await suggestions.distinctBy('storage', { model: 'Galaxy S21' }), ['128GB']);

  // Unknown column names are ignored instead of reaching SQL.
  assert.deepEqual(await suggestions.distinctBy('model', { brand: 'Apple' }), []);
  // distinctBy is raw (no case folding); '8gb' is only collapsed inside options().
  assert.deepEqual(await suggestions.distinctBy('ram'), ['4GB', '6GB', '8GB', '8gb']);
});

test('external TAC API is off by default and, when on, caches what it learns', async () => {
  await migrate();

  // Nothing configured => no request is ever made.
  delete process.env.TAC_API_URL;
  assert.equal(tacApi.enabled(), false);
  assert.equal(await tacApi.lookup('35104463'), null);

  let calls = 0;
  const fake = async (url, init) => {
    calls++;
    assert.match(url, /imei\.example/);
    assert.equal(init.method, 'POST');
    assert.equal(init.headers['X-Api-Key'], 'secret-key');
    assert.deepEqual(JSON.parse(init.body), { query: '35104463' });
    return new Response(JSON.stringify({ found: true, brand: { name: 'Apple' }, model: 'iPhone 13' }));
  };

  process.env.TAC_API_URL = 'https://imei.example/api/v1/tac/lookup';
  process.env.TAC_API_KEY = 'secret-key';
  assert.equal(tacApi.enabled(), true);

  const first = await tacApi.lookup('35104463', fake);
  assert.equal(calls, 1);
  assert.equal(first.brand, 'Apple');
  assert.equal(first.model, 'iPhone 13');
  assert.equal((await db('tac_models').where({ tac: '35104463' }).first()).source, 'api');

  // Second lookup is served from the cache, not the network.
  assert.equal((await tacApi.lookup('35104463', fake)).model, 'iPhone 13');
  assert.equal(calls, 1, 'a known TAC must not be looked up again');

  // A row the shop typed itself is never overwritten by the API.
  await db('tac_models').insert({ tac: '35104464', brand: 'Samsung', model: 'My Own Entry',
    source: 'learned' }).onConflict('tac').merge();
  const kept = await tacApi.lookup('35104464', fake);
  assert.equal(kept.model, 'My Own Entry');

  // Provider failures are swallowed: buying must keep working.
  assert.equal(await tacApi.lookup('35104465', async () => { throw new Error('offline'); }), null);
  assert.equal(await tacApi.lookup('35104466', async () => new Response('nope', { status: 500 })), null);
  assert.equal(await tacApi.lookup('35104467', async () => new Response('{"found":false}')), null);
  assert.equal(await tacApi.lookup('nope', fake), null, 'invalid TAC is rejected before any request');

  // Other response shapes are understood too.
  assert.deepEqual(tacApi.parse({ manufacturer: 'Xiaomi', marketing_name: 'Redmi Note 12' }),
    { brand: 'Xiaomi', model: 'Redmi Note 12' });
  assert.deepEqual(tacApi.parse({ brand: 'Apple', model: null }), { brand: 'Apple', model: null });
  assert.equal(tacApi.parse({ brand: null, model: null }), null);
  assert.equal(tacApi.parse({ found: false, brand: 'Apple', model: 'iPhone' }), null);
  assert.equal(tacApi.parse('not json'), null);

  delete process.env.TAC_API_URL;
  delete process.env.TAC_API_KEY;
});

test('buy flow: serial number, ID photo and Visiting Card are stored; photos stay out of lists', async t => {
  await migrate();
  await db('sales').del(); await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del(); await db('shops').del();

  const app = express();
  app.use(express.json({ limit: '8mb' }));
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

  const admin = await login('superadmin', 'AuditOnly@123');
  const created = await fetch(base + '/admin/shops', { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${admin}` },
    body: JSON.stringify({ name: 'Beta', username: 'ownerB', password: 'OwnerB@123' }) });
  assert.equal(created.status, 200, JSON.stringify(await created.json()));
  const owner = await login('ownerB', 'OwnerB@123');

  // Give the seeded TAC a colour so the dropdown has a leading value.
  await db('tac_models').insert({ tac: '35332811', brand: 'Apple', model: 'iPhone 13', ram: '4GB',
    storage: '128GB', color: 'Midnight', source: 'learned' }).onConflict('tac').merge();

  assert.equal((await request('GET', `/imei/${IMEI_A}`, null)).status, 401, 'IMEI lookup requires a login');

  const seen = await request('GET', `/imei/${IMEI_A}`, owner);
  assert.equal(seen.status, 200);
  assert.equal(seen.body.found, true);
  assert.equal(seen.body.info.brand, 'Apple');
  assert.equal(seen.body.info.model, 'iPhone 13');
  assert.equal(seen.body.options.ram[0], '4GB');
  assert.equal(seen.body.options.storage[0], '128GB');
  assert.equal(seen.body.options.color[0], 'Midnight');
  assert.ok(seen.body.options.ram.length > 1, 'dropdown should offer alternatives too');

  const buy = await request('POST', '/buy', owner, {
    imei: IMEI_A, imei2: '', serial_number: 'C02XK1ZJQ6NV', brand: 'Apple', model: 'iPhone 13',
    ram: '4GB', storage: '128GB', color: 'Midnight', condition: 'Good', accessories: 'Box', buy_price: '31000',
    buy_date: '2026-09-28', seller_name: 'Ramesh', seller_phone: '9876543210',
    seller_id_type: 'Visiting Card', seller_address: 'Mahesana', notes: '', customer_id_photo: PNG,
  });
  assert.equal(buy.status, 200, JSON.stringify(buy.body));

  const row = await db('phones').where({ id: buy.body.id }).first();
  assert.equal(row.serial_number, 'C02XK1ZJQ6NV');
  assert.equal(row.customer_id_photo, PNG);
  assert.equal(row.seller_id_type, 'Visiting Card');

  // The photo must not ride along in list responses (base64 would bloat every
  // stock call) but the detail endpoint returns it.
  const stock = await request('GET', '/stock', owner);
  assert.equal(stock.status, 200);
  assert.equal(stock.body.length, 1);
  assert.equal(stock.body[0].serial_number, 'C02XK1ZJQ6NV');
  assert.ok(!('customer_id_photo' in stock.body[0]));

  const detail = await request('GET', `/phones/${buy.body.id}`, owner);
  assert.equal(detail.body.customer_id_photo, PNG);

  // The IMEI lookup returns this phone in `history` (the app re-fills from it),
  // but those rows must not carry the base64 photo back over the wire.
  const again = await request('GET', `/imei/${IMEI_A}`, owner);
  assert.equal(again.status, 200);
  assert.ok(again.body.history.length > 0, 'history should include the phone just bought');
  assert.equal(again.body.history[0].serial_number, 'C02XK1ZJQ6NV');
  assert.ok(!('customer_id_photo' in again.body.history[0]), 'history must not include the base64 photo');

  // Editing keeps the new fields writable.
  const edited = await request('PUT', `/phones/${buy.body.id}`, owner, { serial_number: 'NEW-SERIAL' });
  assert.equal(edited.status, 200, JSON.stringify(edited.body));
  assert.equal((await db('phones').where({ id: buy.body.id }).first()).serial_number, 'NEW-SERIAL');

  // Bad payloads are rejected at the API boundary.
  const bad = await request('POST', '/buy', owner, { imei: IMEI_B, model: 'X', buy_price: '10',
    customer_id_photo: 'javascript:alert(1)' });
  assert.equal(bad.status, 400);
  assert.match(bad.body.error, /customer_id_photo/);

  const badSerial = await request('POST', '/buy', owner, { imei: IMEI_B, model: 'X', buy_price: '10',
    serial_number: 'x'.repeat(65) });
  assert.equal(badSerial.status, 400);
  assert.match(badSerial.body.error, /serial_number/);

  const badIdType = await request('POST', '/buy', owner, { imei: IMEI_B, model: 'X', buy_price: '10',
    seller_id_type: 'Ration Card' });
  assert.equal(badIdType.status, 400);
  assert.match(badIdType.body.error, /seller_id_type/);
});
