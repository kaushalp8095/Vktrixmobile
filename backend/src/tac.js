// TAC catalog: CSV parsing, safe merge rules and the free Osmocom catalog sync.
//
// Data rules (important for shops):
// - Sync is ADDITIVE: rows are never deleted, so an incomplete/truncated upstream
//   file cannot wipe local data.
// - Only rows previously written by the community sync (source = 'osmocom') are
//   updated by a later sync. Rows learned from real purchases, CSV imports, seed
//   and legacy rows are "protected" and never overwritten by the community data.
// - The community catalog has brand + model only. RAM/storage/colour are never
//   touched by the sync.
const db = require('./db');

const DEFAULT_URL = 'http://tacdb.osmocom.org/export/tacdb.csv';
const SOURCE = Object.freeze({
  OSMOCOM: 'osmocom', LEARNED: 'learned', CSV: 'csv', SEED: 'seed', LEGACY: 'legacy',
});
const CATALOG_INFO = Object.freeze({
  name: 'Osmocom TAC database',
  homepage: 'http://tacdb.osmocom.org/',
  license: 'CC-BY-SA 3.0 Unported',
  attribution: 'TAC data: Osmocom TAC database (c) Harald Welte and contributors, CC-BY-SA 3.0',
});
const LIMITATIONS = Object.freeze([
  'Community catalog is incomplete: many recent and India-only models are missing.',
  'Only brand and model are provided. RAM, storage and colour must still be entered by the shop.',
  'One TAC can cover several variants; names may be model codes (e.g. SM-A515F) instead of marketing names.',
  'Entries are crowd-sourced and not verified by GSMA. Always check the phone itself before buying.',
  'Sync never deletes rows and never overwrites details learned from your own purchases.',
]);
const STALE_RUN_MS = 15 * 60 * 1000;
const FIELD_MAX = 255;

// RFC 4180-style CSV parser: quoted fields, escaped quotes ("") and newlines in quotes.
function parseCsv(text) {
  const rows = [];
  let row = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += ch;
    } else if (ch === '"' && field === '') quoted = true;
    else if (ch === ',') { row.push(field); field = ''; }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(field); rows.push(row); row = []; field = '';
    } else field += ch;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  return rows;
}

const clean = v => {
  if (v == null) return null;
  const s = String(v).replace(/\s+/g, ' ').trim();
  return s ? s.slice(0, FIELD_MAX) : null;
};

// Returns { format, rows: [{tac, brand, model, ram, storage}], invalid, duplicates }.
// Supported: Osmocom export (banner + `tac,name,name,...`), CSV with a header
// row (tac,brand,model,ram,storage in any order), or header-less positional rows.
function parseTacCsv(text) {
  const all = parseCsv(String(text || '').replace(/^\uFEFF/, ''));
  let format = 'positional';
  let cols = { tac: 0, brand: 1, model: 2, ram: 3, storage: 4 };
  let start = 0;
  for (let i = 0; i < Math.min(all.length, 5); i++) {
    const h = all[i].map(x => x.trim().toLowerCase());
    if (h[0] !== 'tac') continue;
    start = i + 1;
    if (h[1] === 'name' && h[2] === 'name') {
      // Osmocom: tac,name(brand),name(model),contributor,comment,gsmarena,gsmarena,aka
      format = 'osmocom';
      cols = { tac: 0, brand: 1, model: 2, ram: -1, storage: -1 };
    } else {
      format = 'header';
      const at = name => h.indexOf(name);
      cols = { tac: 0, brand: at('brand'), model: at('model'), ram: at('ram'), storage: at('storage') };
    }
    break;
  }
  const out = new Map();
  let invalid = 0, duplicates = 0;
  for (let i = start; i < all.length; i++) {
    const c = all[i];
    if (c.length === 1 && !c[0].trim()) continue; // blank line
    const tac = (c[cols.tac] || '').trim();
    const pick = k => (cols[k] >= 0 ? clean(c[cols[k]]) : null);
    const row = { tac, brand: pick('brand'), model: pick('model'), ram: pick('ram'), storage: pick('storage') };
    if (!/^\d{8}$/.test(tac) || (!row.brand && !row.model)) { invalid++; continue; }
    if (out.has(tac)) { duplicates++; continue; } // first entry wins, deterministic
    out.set(tac, row);
  }
  return { format, rows: [...out.values()], invalid, duplicates };
}

// ISO strings sort/compare correctly in SQLite and are cast by PostgreSQL.
const now = () => new Date().toISOString();
const chunks = (arr, n) => Array.from({ length: Math.ceil(arr.length / n) }, (_, i) => arr.slice(i * n, i * n + n));

// Community rows: insert new TACs, refresh only earlier community rows, protect the rest.
async function applyCommunityRows(rows, trxOrDb = db) {
  const existing = new Map((await trxOrDb('tac_models').select('tac', 'brand', 'model', 'source'))
    .map(r => [r.tac, r]));
  const inserts = [], updates = [];
  let unchanged = 0, protectedRows = 0;
  for (const r of rows) {
    const old = existing.get(r.tac);
    if (!old) inserts.push({ tac: r.tac, brand: r.brand, model: r.model, source: SOURCE.OSMOCOM, updated_at: now() });
    else if (old.source !== SOURCE.OSMOCOM) protectedRows++;
    else if ((old.brand || null) !== r.brand || (old.model || null) !== r.model) updates.push(r);
    else unchanged++;
  }
  for (const part of chunks(inserts, 200)) await trxOrDb('tac_models').insert(part);
  for (const r of updates) {
    await trxOrDb('tac_models').where({ tac: r.tac, source: SOURCE.OSMOCOM })
      .update({ brand: r.brand, model: r.model, updated_at: now() });
  }
  return { inserted: inserts.length, updated: updates.length, unchanged, protected: protectedRows };
}

// Admin CSV (tac,brand,model,ram,storage): explicit admin data, may overwrite, but
// only the columns that are actually present/non-empty (never blanks learned RAM).
async function applyAdminRows(rows, trxOrDb = db) {
  let n = 0;
  for (const r of rows) {
    const data = { tac: r.tac, source: SOURCE.CSV, updated_at: now() };
    for (const k of ['brand', 'model', 'ram', 'storage']) if (r[k]) data[k] = r[k];
    const merge = Object.keys(data).filter(k => k !== 'tac');
    await trxOrDb('tac_models').insert(data).onConflict('tac').merge(merge);
    n++;
  }
  return { inserted_or_updated: n };
}

async function downloadText(url, { timeoutMs, maxBytes, fetchImpl = fetch }) {
  const res = await fetchImpl(url, {
    signal: AbortSignal.timeout(timeoutMs), redirect: 'follow',
    headers: { 'User-Agent': 'VktrixMobile-TAC-Sync/1.0', Accept: 'text/csv,text/plain,*/*' },
  });
  if (!res.ok) throw new Error(`Upstream returned HTTP ${res.status}`);
  const declared = Number(res.headers.get('content-length') || 0);
  if (declared > maxBytes) throw new Error(`Upstream file too large (${declared} bytes, max ${maxBytes})`);
  const reader = res.body.getReader();
  const parts = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) { await reader.cancel(); throw new Error(`Upstream file too large (max ${maxBytes} bytes)`); }
    parts.push(value);
  }
  return { text: new TextDecoder('utf-8').decode(Buffer.concat(parts)), bytes: size };
}

function config() {
  return {
    url: process.env.TAC_SYNC_URL || DEFAULT_URL,
    timeoutMs: Number(process.env.TAC_SYNC_TIMEOUT_MS) || 120000,
    maxBytes: (Number(process.env.TAC_SYNC_MAX_MB) || 25) * 1024 * 1024,
    minRows: Number(process.env.TAC_SYNC_MIN_ROWS ?? 100),
  };
}

const runIdOf = row => (typeof row === 'object' ? row.id : row);
let activeRun = null; // in-process lock (Render runs one instance by default)

async function runSync(runId, opts) {
  const cfg = { ...config(), ...opts };
  try {
    const { text, bytes } = await downloadText(cfg.url, cfg);
    const parsed = parseTacCsv(text);
    // Guard against HTML error pages / truncated or garbage responses.
    if (parsed.rows.length < cfg.minRows)
      throw new Error(`Upstream returned only ${parsed.rows.length} valid TAC rows (expected at least ${cfg.minRows}); nothing changed`);
    const result = await db.transaction(trx => applyCommunityRows(parsed.rows, trx));
    await db('tac_sync_runs').where({ id: runId }).update({
      status: 'success', finished_at: now(), bytes, rows_seen: parsed.rows.length,
      invalid: parsed.invalid + parsed.duplicates, inserted: result.inserted, updated: result.updated,
      unchanged: result.unchanged, protected: result.protected,
    });
  } catch (err) {
    const message = err?.name === 'TimeoutError' ? `Upstream timed out after ${cfg.timeoutMs} ms` : String(err?.message || err);
    await db('tac_sync_runs').where({ id: runId }).update({ status: 'failed', finished_at: now(), error: message.slice(0, 1000) })
      .catch(e => console.error('TAC sync status update failed:', e));
  }
}

// Starts a background sync. Returns { started, run } (started=false if one is running).
async function startSync({ userId = null, ...opts } = {}) {
  if (activeRun) return { started: false, run: await db('tac_sync_runs').where({ id: activeRun.id }).first() };
  const staleBefore = new Date(Date.now() - STALE_RUN_MS).toISOString();
  // Rows left "running" by a crash/restart are marked failed so they don't block forever.
  await db('tac_sync_runs').where({ status: 'running' }).andWhere('started_at', '<', staleBefore)
    .update({ status: 'failed', finished_at: now(), error: 'Interrupted (server restarted or timed out)' });
  const running = await db('tac_sync_runs').where({ status: 'running' }).first();
  if (running) return { started: false, run: running };
  const cfg = { ...config(), ...opts };
  const [row] = await db('tac_sync_runs').insert({
    source: SOURCE.OSMOCOM, url: cfg.url, status: 'running', started_at: now(), started_by: userId,
  }).returning('id');
  const id = runIdOf(row);
  const promise = runSync(id, opts).finally(() => { if (activeRun?.id === id) activeRun = null; });
  activeRun = { id, promise };
  return { started: true, run: await db('tac_sync_runs').where({ id }).first(), promise };
}

async function status() {
  const bySource = await db('tac_models').select('source').count('* as n').groupBy('source');
  const counts = Object.fromEntries(bySource.map(r => [r.source || SOURCE.LEGACY, Number(r.n)]));
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  const recent = await db('tac_sync_runs').orderBy('id', 'desc').limit(5);
  const lastSuccess = await db('tac_sync_runs').where({ status: 'success' }).orderBy('id', 'desc').first();
  return {
    total, counts, running: recent.find(r => r.status === 'running') || null,
    last_run: recent[0] || null, last_success: lastSuccess || null, recent,
    catalog: { ...CATALOG_INFO, url: config().url }, limitations: LIMITATIONS,
  };
}

module.exports = {
  DEFAULT_URL, SOURCE, CATALOG_INFO, LIMITATIONS,
  parseCsv, parseTacCsv, applyCommunityRows, applyAdminRows, downloadText, startSync, status,
  _activeRun: () => activeRun,
};
