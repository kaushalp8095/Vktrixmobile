// Extended free TAC catalog (MoazEb/tac-database, MIT): parsing, sync, merge rules,
// mirror fallback, admin import and the super-admin API.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

if (process.env.TEST_DATABASE_URL) {
  const dbName = new URL(process.env.TEST_DATABASE_URL).pathname.split('/').filter(Boolean).pop() || '';
  if (!/(^|_)test($|_)/i.test(dbName)) throw new Error('Refusing PostgreSQL tests unless database name includes "test"');
  process.env.DB_CLIENT = 'pg';
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
} else {
  process.env.DB_CLIENT = 'better-sqlite3';
  process.env.SQLITE_FILE = path.join(os.tmpdir(), `vktrix-tacdb-${process.pid}.sqlite`);
  for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
}
process.env.JWT_SECRET = 'isolated-test-secret-never-use-in-production';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';
process.env.TAC_SYNC_MIN_ROWS = '2';
process.env.TAC_SYNC_TIMEOUT_MS = '5000';
process.env.TAC_SYNC_TACDB_MIN_ROWS = '2';
process.env.TAC_SYNC_TACDB_TIMEOUT_MS = '5000';

const express = require('express');
const db = require('../src/db');
const migrate = require('../src/migrate');
const TAC = require('../src/tac');

// Shape of the real tac_full.csv: header, quoted SPECS with internal model code,
// region, year and chipset, plain unquoted rows, junk and duplicates.
const tacdb = rows => ['Brand,TAC,SPECS', ...rows].join('\n') + '\n';
const UPSTREAM_V1 = tacdb([
  '"REDMI",86166507,"REDMI 13 5G, Xiaomi 2406ERN9CI, India Model, 2024, QC SD 4 Gen 2 AE"',
  '"POCO",86142108,"POCO C85 5G, Xiaomi 2508CPC2BI, India Model, 2025"',
  '"SAMSUNG",35332811,"SAMSUNG GALAXY A55 5G, Samsung SM-A556B2024"',
  '"ITEL",35134328,"ITEL, ITEL A70"',
  'Nokia,49013920,Nokia 1610',                                    // unquoted row
  '"OLD_PHONES",,',                                               // junk: no TAC and no specs
  'notatac,123,Broken',                                           // junk: bad TAC
  '"XIAOMI",86166507,"DUPLICATE, ignored"',                       // duplicate TAC
]);
const UPSTREAM_V2 = tacdb([
  '"REDMI",86166507,"REDMI 13 5G, Xiaomi 2406ERN9CI, India Model, 2024, QC SD 4 Gen 2 AE"', // unchanged
  '"VIVO",86000010,"VIVO Y28 5G, Vivo V2324, India Model, 2024"',  // new
  '"POCO",86142108,"POCO C85 5G, Xiaomi 2509CPC2BI, India Model, 2025"', // renamed upstream -> updated
]);
const MIRROR_CSV = 'Brand,TAC,SPECS\n"Nokia",35250500,"Nokia 6820"\n';
const TEST_TACS = ['86166507', '86142108', '35134328', '49013920', '86000010', '86199999', '35332811', '86900001'];

let upstream = { status: 200, body: UPSTREAM_V1, hold: null };
let server, upstreamServer, base, upstreamPort;

async function request(method, route, token, data) {
  const response = await fetch(base + route, {
    method,
    headers: { ...(data instanceof FormData ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(data === undefined ? {} : { body: data instanceof FormData ? data : JSON.stringify(data) }),
  });
  return { status: response.status, body: await response.json() };
}
async function login(username, password) {
  const r = await request('POST', '/auth/login', null, { username, password });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.token;
}
const tacRow = tac => db('tac_models').where({ tac }).first();
async function syncNow(admin, source) {
  const r = await request('POST', `/admin/tac/sync/${source}`, admin);
  assert.equal(r.status, 202, JSON.stringify(r.body));
  await TAC._activeRun()?.promise;
  return (await request('GET', '/admin/tac/status', admin)).body;
}

test('extended CSV parser: brand + model (with model code), junk and duplicates', () => {
  const parsed = TAC.parseTacdbCsv(UPSTREAM_V1);
  assert.equal(parsed.format, 'tacdb');
  assert.equal(parsed.invalid, 2);
  assert.equal(parsed.duplicates, 1);
  assert.equal(parsed.rows.length, 5, 'the duplicate keeps the first (better) entry');
  const byTac = new Map(parsed.rows.map(r => [r.tac, r]));
  assert.deepEqual(byTac.get('86166507'), { tac: '86166507', brand: 'REDMI', model: '13 5G (2406ERN9CI)', ram: null, storage: null });
  assert.equal(byTac.get('35332811').model, 'GALAXY A55 5G (SM-A556B)');
  assert.equal(byTac.get('35134328').model, 'A70');
  assert.equal(byTac.get('49013920').model, '1610');
  // A file without the header row is still parsed, and the admin CSV importer
  // recognises the extended export on its own.
  assert.equal(TAC.parseTacdbCsv(MIRROR_CSV).rows[0].model, '6820');
  assert.equal(TAC.parseTacCsv(UPSTREAM_V1).format, 'tacdb');
  assert.equal(TAC.parseTacCsv('12345678,Apple,iPhone 13,4GB,128GB\n').format, 'positional');
});

test('model extraction keeps what a shop needs and drops the rest', () => {
  const m = TAC.modelFromSpecs;
  assert.equal(m('XIAOMI', 'XIAOMI REDMI 15C, Xiaomi 25078RA3EY2025'), 'REDMI 15C (25078RA3EY)');
  assert.equal(m('POCO', 'POCO C75, Xiaomi 2410FPCC5I, Poco M7 (India Model), 2024, MT D 6020'), 'C75 (2410FPCC5I)');
  assert.equal(m('SAMSUNG', 'SAMSUNG GALAXY A55 5G, Samsung SM-A556B2024'), 'GALAXY A55 5G (SM-A556B)');
  assert.equal(m('SAMSUNG', 'SAMSUNG GALAXY S4 LTE, Samsung Galaxy S4 LTE2013'), 'GALAXY S4 LTE');
  assert.equal(m('OPPO', 'OPPO A7, CPH1901'), 'A7 (CPH1901)', 'a 4-digit code that is not a glued year is kept');
  assert.equal(m('REALME', 'REALME GT 6T, Chongqing RMX38532024'), 'GT 6T (RMX3853)');
  assert.equal(m('APPLE', 'APPLE IPHONE 13, Apple A2633'), 'IPHONE 13 (A2633)');
  assert.equal(m('ITEL', 'ITEL, ITEL A70'), 'A70');
  assert.equal(m('SAMSUNG', 'SAMSUNG, SAMSUNG SGH-T229'), 'SGH-T229');
  assert.equal(m('nokia', 'Nokia 1610'), '1610');
  assert.equal(m('SAMSUNG', 'SAMSUNG GALAXY S20+ 5G, Samsung SM-G986N, Global Model, 2020'), 'GALAXY S20+ 5G (SM-G986N)');
  assert.equal(m('OLD_PHONES', ''), null);
  assert.equal(m('XIAOMI', null), null);
});

test('mirror fallback: a broken first URL does not stop the sync', async () => {
  const calls = [];
  const fetchImpl = async url => {
    calls.push(url);
    if (calls.length === 1) return new Response('down', { status: 503 });
    return new Response(MIRROR_CSV, { status: 200 });
  };
  const r = await TAC.downloadText(['http://a.tac/first', 'http://b.tac/mirror'], { timeoutMs: 1000, maxBytes: 1024, fetchImpl });
  assert.deepEqual(calls, ['http://a.tac/first', 'http://b.tac/mirror']);
  assert.equal(r.url, 'http://b.tac/mirror');
  assert.equal(r.bytes, Buffer.byteLength(MIRROR_CSV));
  assert.match(r.text, /6820/);
});

test('extended catalog sync: status, merge rules, re-sync, failures and access control', async t => {
  await migrate();
  await migrate(); // idempotent
  await db('sales').del(); await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del(); await db('shops').del();
  await db('tac_sync_runs').del();
  // Rows that must survive every free sync: an admin CSV import and an Osmocom row.
  await db('tac_models').whereIn('tac', TEST_TACS).del();
  await db('tac_models').insert([
    { tac: '86900001', brand: 'AdminBrand', model: 'Admin Name', ram: '8GB', storage: '256GB', source: 'csv' },
    { tac: '35332811', brand: 'Apple', model: 'iPhone 13 (community)', source: 'osmocom' },
  ]);

  upstreamServer = http.createServer(async (req, res) => {
    if (upstream.hold) await upstream.hold;
    res.writeHead(upstream.status, { 'Content-Type': 'text/csv; charset=utf-8' });
    res.end(upstream.body);
  });
  upstreamServer.listen(0, '127.0.0.1');
  await new Promise(resolve => upstreamServer.once('listening', resolve));
  upstreamPort = upstreamServer.address().port;
  process.env.TAC_SYNC_TACDB_URL = `http://127.0.0.1:${upstreamPort}/tac_full.csv`;
  process.env.TAC_SYNC_URL = `http://127.0.0.1:${upstreamPort}/tacdb.csv`;

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
    await new Promise(resolve => upstreamServer.close(resolve));
    await db.destroy();
    if (!process.env.TEST_DATABASE_URL)
      for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
  });

  const admin = await login('superadmin', 'AuditOnly@123');
  const shop = await request('POST', '/admin/shops', admin, { name: 'Alpha', username: 'ownerA', password: 'OwnerA@123' });
  assert.equal(shop.status, 200, JSON.stringify(shop.body));
  const owner = await login('ownerA', 'OwnerA@123');

  await t.test('status lists both free catalogs with their licence and limitations', async () => {
    const s = (await request('GET', '/admin/tac/status', admin)).body;
    assert.deepEqual(s.catalogs.map(c => c.source), ['osmocom', 'tacdb']);
    const extended = s.catalogs[1];
    assert.match(extended.label, /Extended/);
    assert.equal(extended.license, 'MIT');
    assert.match(extended.attribution, /MoazEb\/tac-database/);
    assert.equal(extended.homepage, 'https://github.com/MoazEb/tac-database');
    assert.ok(extended.note.length > 20, 'the app shows this note under the sync button');
    assert.equal(extended.last_run, null);
    assert.equal(s.catalogs[0].license, 'CC-BY-SA 3.0 Unported');
    assert.ok(s.limitations.some(x => /third-party/i.test(x)));
    assert.ok(s.local.some(l => l.source === 'learned'));
    assert.equal(s.external_api.enabled, false, 'no paid API is configured');
  });

  await t.test('only super admin can sync an individual catalog', async () => {
    assert.equal((await request('POST', '/admin/tac/sync/tacdb', owner)).status, 403);
    assert.equal((await request('POST', '/admin/tac/sync/nope', admin)).status, 404);
    assert.equal((await request('POST', '/admin/tac/sync/nope', null)).status, 401);
  });

  await t.test('sync inserts extended rows, keeps CSV/Osmocom rows and never deletes', async () => {
    const s = await syncNow(admin, 'tacdb');
    assert.equal(s.last_run.status, 'success', JSON.stringify(s.last_run));
    assert.equal(s.last_run.source, 'tacdb');
    assert.equal(s.last_run.rows_seen, 5);
    assert.equal(s.last_run.inserted, 4);
    assert.equal(s.last_run.protected, 1, 'the existing Osmocom row is left alone by default');
    assert.equal(s.last_run.invalid, 3, 'junk rows and the duplicate are skipped');
    assert.match(s.last_run.url, new RegExp(`127\\.0\\.0\\.1:${upstreamPort}`));

    const redmi = await tacRow('86166507');
    assert.deepEqual([redmi.brand, redmi.model, redmi.ram, redmi.storage, redmi.source],
      ['REDMI', '13 5G (2406ERN9CI)', null, null, 'tacdb']);
    assert.equal((await tacRow('35134328')).model, 'A70');
    assert.equal((await tacRow('35332811')).model, 'iPhone 13 (community)', 'Osmocom rows stay until a shop learns them');
    const adminRow = await tacRow('86900001');
    assert.deepEqual([adminRow.model, adminRow.ram, adminRow.source], ['Admin Name', '8GB', 'csv']);
    assert.equal(s.counts.tacdb, 4);
    assert.equal(s.catalogs[1].count, 4);
    assert.equal(s.catalogs[1].last_success.id, s.last_run.id);
    assert.equal(s.catalogs[0].last_run, null, 'the Osmocom catalog has its own run history');
  });

  await t.test('IMEI lookup serves extended rows as unverified community data', async () => {
    const r = await request('GET', '/imei/861665070000009', owner);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.found, true);
    assert.equal(r.body.tac, '86166507');
    assert.equal(r.body.info.brand, 'REDMI');
    assert.equal(r.body.info.source, 'tacdb');
    assert.equal(r.body.info.ram, null);
  });

  await t.test('a real purchase wins: learned stays learned over later extended syncs', async () => {
    const buy = await request('POST', '/buy', owner, { imei: '861665070000009', brand: 'Redmi', model: '13 5G',
      ram: '6GB', storage: '128GB', condition: 'Good', buy_price: '8000', buy_date: '2025-01-01' });
    assert.equal(buy.status, 200, JSON.stringify(buy.body));
    assert.equal((await tacRow('86166507')).source, 'learned');
    upstream = { status: 200, body: UPSTREAM_V2, hold: null };
    const s = await syncNow(admin, 'tacdb');
    assert.equal(s.last_run.inserted, 1, 'only the new Vivo TAC is added');
    assert.equal(s.last_run.updated, 1, 'the extended row upstream renamed is refreshed');
    assert.equal(s.last_run.protected, 1, 'the learned row is protected');
    const learned = await tacRow('86166507');
    assert.deepEqual([learned.model, learned.ram, learned.source], ['13 5G', '6GB', 'learned']);
    assert.equal((await tacRow('86000010')).model, 'Y28 5G (V2324)');
    assert.equal((await tacRow('86142108')).model, 'C85 5G (2509CPC2BI)');
  });

  await t.test('re-syncing the same file changes nothing', async () => {
    upstream = { status: 200, body: UPSTREAM_V2, hold: null };
    const s = await syncNow(admin, 'tacdb');
    assert.equal(s.last_run.inserted, 0);
    assert.equal(s.last_run.updated, 0);
    assert.equal(s.last_run.unchanged, 2);
    assert.equal(s.last_run.protected, 1);
  });

  await t.test('one sync at a time across catalogs, and the app reflects a running run', async () => {
    let release;
    upstream = { status: 200, body: UPSTREAM_V2, hold: new Promise(r => { release = r; }) };
    const first = await request('POST', '/admin/tac/sync/tacdb', admin);
    assert.equal(first.status, 202, JSON.stringify(first.body));
    const other = await request('POST', '/admin/tac/sync/osmocom', admin);
    assert.equal(other.status, 409);
    assert.equal(other.body.run.id, first.body.run.id);
    release();
    await TAC._activeRun()?.promise;
    assert.equal((await request('GET', '/admin/tac/status', admin)).body.running, null);
  });

  await t.test('failed or garbage upstream responses are recorded and change nothing', async () => {
    const before = await db('tac_models').count('* as n').first();
    upstream = { status: 503, body: 'down', hold: null };
    let s = await syncNow(admin, 'tacdb');
    assert.equal(s.last_run.status, 'failed');
    assert.match(s.last_run.error, /HTTP 503/);
    upstream = { status: 200, body: '<html><body>Maintenance</body></html>', hold: null };
    s = await syncNow(admin, 'tacdb');
    assert.equal(s.last_run.status, 'failed');
    assert.match(s.last_run.error, /nothing changed/);
    assert.equal(s.catalogs[1].last_success.status, 'success');
    assert.equal(Number((await db('tac_models').count('* as n').first()).n), Number(before.n));
  });

  await t.test('opting in with TAC_SYNC_TACDB_REFRESH_OSMOCOM lets the extended list improve Osmocom rows', async () => {
    process.env.TAC_SYNC_TACDB_REFRESH_OSMOCOM = 'true';
    try {
      upstream = { status: 200, body: UPSTREAM_V1, hold: null };
      const s = await syncNow(admin, 'tacdb');
      assert.equal(s.last_run.updated, 1);
      assert.equal(s.last_run.protected, 1);
      const row = await tacRow('35332811');
      assert.deepEqual([row.brand, row.model, row.source], ['SAMSUNG', 'GALAXY A55 5G (SM-A556B)', 'tacdb']);
      assert.equal((await tacRow('86900001')).source, 'csv', 'admin CSV data is never touched');
    } finally {
      delete process.env.TAC_SYNC_TACDB_REFRESH_OSMOCOM;
    }
  });

  await t.test('admin CSV import understands the extended export and stays non-destructive', async () => {
    const form = new FormData();
    form.append('file', new Blob([tacdb(['"REALME",86199999,"REALME P1 Pro, Realme RMX3989, India Model, 2025"'])]), 'tac_full.csv');
    const r = await request('POST', '/admin/tac/import', admin, form);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.format, 'tacdb');
    assert.equal(r.body.inserted, 1);
    assert.deepEqual([(await tacRow('86199999')).brand, (await tacRow('86199999')).model], ['REALME', 'P1 Pro (RMX3989)']);

    const again = new FormData();
    again.append('file', new Blob([UPSTREAM_V1]), 'tac_full.csv');
    const r2 = await request('POST', '/admin/tac/import', admin, again);
    assert.equal(r2.status, 200, JSON.stringify(r2.body));
    assert.equal((await tacRow('86166507')).source, 'learned', 'the shop purchase is never overwritten by an import');
    assert.equal((await tacRow('86900001')).source, 'csv');
  });
});
