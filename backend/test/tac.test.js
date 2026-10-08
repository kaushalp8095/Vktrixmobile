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
  process.env.SQLITE_FILE = path.join(os.tmpdir(), `vktrix-tac-${process.pid}.sqlite`);
  for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
}
process.env.JWT_SECRET = 'isolated-test-secret-never-use-in-production';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';
process.env.TAC_SYNC_MIN_ROWS = '2';
process.env.TAC_SYNC_TIMEOUT_MS = '5000';

const express = require('express');
const db = require('../src/db');
const migrate = require('../src/migrate');
const TAC = require('../src/tac');

// Shape of the real export: banner line, duplicate "name" headers, quoted aka list.
const osmocom = rows => [
  'Osmocom TAC database under CC-BY-SA v3.0 (c) Harald Welte 2016',
  'tac,name,name,contributor,comment,gsmarena,gsmarena,aka',
  ...rows,
].join('\n') + '\n';
const UPSTREAM_V1 = osmocom([
  '35104463,Apple,iPhone 13,tacdb submission,,,http://www.gsmarena.com/apple-phones-48.php,',
  '86751306,Xiaomi,Redmi 9A,tacdb submission,,,,',
  '35332811,Apple,iPhone 13 (community),someone,,,,',          // seed row: protected
  '99000001,Legacy,Upstream Name,someone,,,,',                  // legacy row: protected
  '49013920,Nokia,1610,OsmoDevCon 2014,,,,"1610+,1611,1611+,NHE-5NX"',
  '35000001,Samsung,"SM-A515F/DSN, ""Galaxy A51""",x,,,,',
  '35000001,Samsung,Duplicate ignored,x,,,,',
  'notatac,Bad,Row,,,,,',
]);
const UPSTREAM_V2 = osmocom([
  '35104463,Apple,iPhone 13 Mini,tacdb submission,,,,',         // changed community row -> updated
  '86751306,Xiaomi,Redmi 9A,tacdb submission,,,,',              // unchanged
  '86000002,OnePlus,Nord CE,tacdb submission,,,,',              // new
]);

let upstream = { status: 200, body: UPSTREAM_V1, hold: null };
let server, upstreamServer, base;

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
async function syncNow(admin) {
  const r = await request('POST', '/admin/tac/sync', admin);
  assert.equal(r.status, 202, JSON.stringify(r.body));
  await TAC._activeRun()?.promise;
  return (await request('GET', '/admin/tac/status', admin)).body;
}

test('CSV parser handles quotes, escaped quotes, CRLF and newlines inside quotes', () => {
  assert.deepEqual(TAC.parseCsv('a,"b,c","d ""e"""\r\n1,"multi\nline",3'), [
    ['a', 'b,c', 'd "e"'], ['1', 'multi\nline', '3'],
  ]);
  assert.deepEqual(TAC.parseCsv('x,5" screen,y'), [['x', '5" screen', 'y']]);
});

test('TAC CSV formats: Osmocom never maps contributor/comment into RAM/storage', () => {
  const o = TAC.parseTacCsv(UPSTREAM_V1);
  assert.equal(o.format, 'osmocom');
  assert.equal(o.invalid, 1);
  assert.equal(o.duplicates, 1);
  const nokia = o.rows.find(r => r.tac === '49013920');
  assert.deepEqual(nokia, { tac: '49013920', brand: 'Nokia', model: '1610', ram: null, storage: null });
  assert.equal(o.rows.find(r => r.tac === '35000001').model, 'SM-A515F/DSN, "Galaxy A51"');

  const h = TAC.parseTacCsv('\uFEFFtac,model,brand,storage\n12345678, Galaxy  S21 ,Samsung,128GB\n');
  assert.equal(h.format, 'header');
  assert.deepEqual(h.rows[0], { tac: '12345678', brand: 'Samsung', model: 'Galaxy S21', ram: null, storage: '128GB' });

  const p = TAC.parseTacCsv('12345678,Apple,iPhone 13,4GB,128GB\n1234567,Too,Short\n87654321,,\n');
  assert.equal(p.format, 'positional');
  assert.equal(p.rows.length, 1); assert.equal(p.invalid, 2);
  assert.equal(p.rows[0].ram, '4GB');
});

test('download enforces the size cap', async () => {
  const big = new Response('x'.repeat(2048));
  await assert.rejects(TAC.downloadText('http://unused', { timeoutMs: 1000, maxBytes: 1024, fetchImpl: async () => big }),
    /too large/);
});

test('free TAC catalog sync: migration, protection rules, re-sync, failures and access control', async t => {
  if (!process.env.TEST_DATABASE_URL) {
    // Simulate an existing deployment: old tac_models table without `source`.
    await db.schema.createTable('tac_models', tb => {
      tb.string('tac', 8).primary(); tb.string('brand'); tb.string('model');
      tb.string('ram'); tb.string('storage'); tb.string('color'); tb.timestamp('updated_at');
    });
    await db('tac_models').insert({ tac: '99000001', brand: 'Legacy', model: 'Learned Before', ram: '6GB', storage: '128GB' });
  }
  await migrate();
  await migrate(); // idempotent
  await db('sales').del(); await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del(); await db('shops').del();
  await db('tac_sync_runs').del();
  await db('tac_models').whereNotIn('source', ['seed', 'legacy']).del();
  if (process.env.TEST_DATABASE_URL) {
    await db('tac_models').insert({ tac: '99000001', brand: 'Legacy', model: 'Learned Before', ram: '6GB', storage: '128GB', source: 'legacy' })
      .onConflict('tac').merge();
  }

  upstreamServer = http.createServer(async (req, res) => {
    if (upstream.hold) await upstream.hold;
    res.writeHead(upstream.status, { 'Content-Type': 'text/csv; charset=utf-8' });
    res.end(upstream.body);
  });
  upstreamServer.listen(0, '127.0.0.1');
  await new Promise(resolve => upstreamServer.once('listening', resolve));
  process.env.TAC_SYNC_URL = `http://127.0.0.1:${upstreamServer.address().port}/tacdb.csv`;

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
  assert.equal(shop.status, 200);
  const owner = await login('ownerA', 'OwnerA@123');

  await t.test('migration backfills provenance for existing rows', async () => {
    assert.equal((await tacRow('99000001')).source, 'legacy');
    assert.equal((await tacRow('35332811')).source, 'seed');
  });

  await t.test('only super admin can view or start the sync', async () => {
    assert.equal((await request('POST', '/admin/tac/sync', owner)).status, 403);
    assert.equal((await request('GET', '/admin/tac/status', owner)).status, 403);
    assert.equal((await request('POST', '/admin/tac/sync', null)).status, 401);
  });

  await t.test('status exposes source, licence and limitations before any run', async () => {
    const s = await request('GET', '/admin/tac/status', admin);
    assert.equal(s.status, 200);
    assert.equal(s.body.last_run, null);
    assert.match(s.body.catalog.license, /CC-BY-SA/);
    assert.ok(s.body.limitations.some(x => /incomplete/i.test(x)));
    assert.ok(s.body.limitations.some(x => /RAM/.test(x)));
  });

  await t.test('first sync inserts community rows, protects seed/legacy rows, rejects parallel runs', async () => {
    let release;
    upstream = { status: 200, body: UPSTREAM_V1, hold: new Promise(r => { release = r; }) };
    const first = await request('POST', '/admin/tac/sync', admin);
    assert.equal(first.status, 202, JSON.stringify(first.body));
    assert.equal(first.body.run.status, 'running');
    const parallel = await request('POST', '/admin/tac/sync', admin);
    assert.equal(parallel.status, 409);
    assert.equal(parallel.body.run.id, first.body.run.id);
    assert.equal((await request('GET', '/admin/tac/status', admin)).body.running.id, first.body.run.id);
    release();
    await TAC._activeRun()?.promise;

    const s = (await request('GET', '/admin/tac/status', admin)).body;
    assert.equal(s.running, null);
    assert.equal(s.last_run.status, 'success', JSON.stringify(s.last_run));
    assert.equal(s.last_run.rows_seen, 6);
    assert.equal(s.last_run.inserted, 4);
    assert.equal(s.last_run.protected, 2);
    assert.equal(s.last_run.invalid, 2);
    assert.equal(s.counts.osmocom, 4);
    assert.equal(s.last_success.id, s.last_run.id);

    const legacy = await tacRow('99000001');
    assert.equal(legacy.model, 'Learned Before'); assert.equal(legacy.ram, '6GB');
    assert.equal((await tacRow('35332811')).model, 'iPhone 13');
    const synced = await tacRow('86751306');
    assert.deepEqual([synced.brand, synced.model, synced.ram, synced.storage, synced.source],
      ['Xiaomi', 'Redmi 9A', null, null, 'osmocom']);
  });

  await t.test('IMEI lookup reports community source so the app can ask to verify', async () => {
    const r = await request('GET', '/imei/867513060000001', owner);
    assert.equal(r.status, 200);
    assert.equal(r.body.found, true);
    assert.equal(r.body.info.source, 'osmocom');
    assert.equal(r.body.info.ram, null);
  });

  await t.test('a real purchase turns the row into learned data that later syncs never overwrite', async () => {
    const buy = await request('POST', '/buy', owner, { imei: '867513060000001', brand: 'Redmi', model: '9A Sport',
      ram: '2GB', storage: '32GB', condition: 'Good', buy_price: '1500', buy_date: '2024-01-01' });
    assert.equal(buy.status, 200, JSON.stringify(buy.body));
    assert.equal((await tacRow('86751306')).source, 'learned');
  });

  await t.test('re-sync updates only community rows, adds new TACs and never deletes', async () => {
    upstream = { status: 200, body: UPSTREAM_V2, hold: null };
    const s = await syncNow(admin);
    assert.equal(s.last_run.status, 'success', JSON.stringify(s.last_run));
    assert.equal(s.last_run.inserted, 1);
    assert.equal(s.last_run.updated, 1);
    assert.equal(s.last_run.protected, 1);
    assert.equal((await tacRow('35104463')).model, 'iPhone 13 Mini');
    const learned = await tacRow('86751306');
    assert.deepEqual([learned.model, learned.ram, learned.source], ['9A Sport', '2GB', 'learned']);
    assert.ok(await tacRow('49013920'), 'rows missing upstream are kept');
    assert.equal((await tacRow('86000002')).brand, 'OnePlus');
  });

  await t.test('failed or garbage upstream responses are recorded and change nothing', async () => {
    const before = await db('tac_models').count('* as n').first();
    upstream = { status: 503, body: 'down', hold: null };
    let s = await syncNow(admin);
    assert.equal(s.last_run.status, 'failed');
    assert.match(s.last_run.error, /HTTP 503/);
    upstream = { status: 200, body: '<html><body>Maintenance</body></html>', hold: null };
    s = await syncNow(admin);
    assert.equal(s.last_run.status, 'failed');
    assert.match(s.last_run.error, /nothing changed/);
    assert.equal(s.last_success.status, 'success');
    const after = await db('tac_models').count('* as n').first();
    assert.equal(Number(after.n), Number(before.n));
  });

  await t.test('CSV import: Osmocom export is non-destructive; admin CSV keeps unspecified columns', async () => {
    const form = new FormData();
    form.append('file', new Blob([osmocom(['99000001,Upstream,Overwrite Attempt,contrib,comment,,,', '86000003,Vivo,Y20,contrib,comment,,,'])]), 'tacdb.csv');
    const o = await request('POST', '/admin/tac/import', admin, form);
    assert.equal(o.status, 200, JSON.stringify(o.body));
    assert.equal(o.body.format, 'osmocom');
    assert.equal(o.body.inserted, 1); assert.equal(o.body.protected, 1);
    assert.equal((await tacRow('99000001')).model, 'Learned Before');
    assert.equal((await tacRow('86000003')).ram, null, 'contributor column must not become RAM');

    const admin2 = new FormData();
    admin2.append('file', new Blob(['99000001,Legacy,Fixed Name\n']), 'mine.csv');
    const a = await request('POST', '/admin/tac/import', admin, admin2);
    assert.equal(a.status, 200, JSON.stringify(a.body));
    const row = await tacRow('99000001');
    assert.deepEqual([row.model, row.ram, row.storage, row.source], ['Fixed Name', '6GB', '128GB', 'csv']);

    const empty = new FormData();
    empty.append('file', new Blob(['hello\n']), 'bad.csv');
    assert.equal((await request('POST', '/admin/tac/import', admin, empty)).status, 400);
  });

  await t.test('a restart marks orphaned running rows as failed', async () => {
    const [row] = await db('tac_sync_runs').insert({ source: 'osmocom', status: 'running', started_at: new Date().toISOString() }).returning('id');
    await migrate();
    const id = typeof row === 'object' ? row.id : row;
    const r = await db('tac_sync_runs').where({ id }).first();
    assert.equal(r.status, 'failed'); assert.match(r.error, /restart/);
  });
});
