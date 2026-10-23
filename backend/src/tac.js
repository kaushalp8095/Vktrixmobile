// TAC catalog: CSV parsing, safe merge rules and the free catalog syncs.
//
// Two free upstream catalogs can be synced by the super admin:
//   1. osmocom - Osmocom TAC database (CC-BY-SA 3.0), tens of thousands of rows,
//                brand + model only.
//   2. tacdb   - MoazEb/tac-database (MIT), ~250k rows, includes recent India-only
//                Redmi/Realme/Poco/Vivo variants and internal model codes.
//
// Data rules (important for shops):
// - Sync is ADDITIVE: rows are never deleted, so an incomplete/truncated upstream
//   file cannot wipe local data.
// - Only rows written by a free catalog sync are refreshed by a later sync of that
//   catalog (see `refreshFrom`). Rows learned from real purchases, CSV imports,
//   seed and legacy rows are "protected" and never overwritten by free data.
// - The free catalogs have brand + model only. RAM/storage/colour are never
//   touched by a sync.
const db = require('./db');

const SOURCE = Object.freeze({
  OSMOCOM: 'osmocom', TACDB: 'tacdb', LEARNED: 'learned',
  CSV: 'csv', API: 'api', SEED: 'seed', LEGACY: 'legacy',
});

// Free community catalogs. `refreshFrom` lists other community sources this
// catalog is allowed to improve (never includes learned/csv/api/seed/legacy).
const CATALOGS = Object.freeze({
  [SOURCE.OSMOCOM]: {
    source: SOURCE.OSMOCOM,
    label: 'Community catalog (Osmocom)',
    short: 'Osmocom',
    note: 'Free community list (brand + model only). Weakest for recent India-only phones.',
    homepage: 'https://tacdb.osmocom.org/',
    license: 'CC-BY-SA 3.0 Unported',
    attribution: 'TAC data: Osmocom TAC database (c) Harald Welte and contributors, CC-BY-SA 3.0',
    // HTTPS hi: plain HTTP par MITM koi bhi brand/model inject kar sakta tha,
    // aur wahi data aage har shop ke buy form me dikhta hai.
    defaultUrls: ['https://tacdb.osmocom.org/export/tacdb.csv'],
    env: { urls: 'TAC_SYNC_URL', timeout: 'TAC_SYNC_TIMEOUT_MS', maxMB: 'TAC_SYNC_MAX_MB', minRows: 'TAC_SYNC_MIN_ROWS' },
    defaults: { timeoutMs: 120000, maxMb: 25, minRows: 100 },
    format: 'osmocom',
    refreshFrom: [],
  },
  [SOURCE.TACDB]: {
    source: SOURCE.TACDB,
    label: 'Extended catalog (India models)',
    short: 'Extended',
    note: 'Free third-party list of ~250k TACs with recent India/global variants and internal model codes. First run takes a few minutes.',
    homepage: 'https://github.com/MoazEb/tac-database',
    license: 'MIT',
    attribution: 'TAC data: MoazEb/tac-database (MIT), community maintained from public databases',
    defaultUrls: [
      'https://raw.githubusercontent.com/MoazEb/tac-database/main/tac_full.csv',
      'https://cdn.jsdelivr.net/gh/MoazEb/tac-database@main/tac_full.csv',
    ],
    env: { urls: 'TAC_SYNC_TACDB_URL', timeout: 'TAC_SYNC_TACDB_TIMEOUT_MS', maxMB: 'TAC_SYNC_TACDB_MAX_MB', minRows: 'TAC_SYNC_TACDB_MIN_ROWS' },
    defaults: { timeoutMs: 300000, maxMb: 30, minRows: 150000 },
    format: 'tacdb',
    // Each catalog owns the rows it wrote: an existing Osmocom row is left as it
    // is (predictable, and prevents trading a good name for a worse one). Set
    // TAC_SYNC_TACDB_REFRESH_OSMOCOM=true to let the extended list improve them.
    refreshFrom: [],
  },
});
const CATALOG_KEYS = Object.freeze(Object.keys(CATALOGS));
// Backwards compatible "catalog" block (older app builds read this one).
const CATALOG_INFO = Object.freeze({
  name: 'Osmocom TAC database',
  homepage: CATALOGS[SOURCE.OSMOCOM].homepage,
  license: CATALOGS[SOURCE.OSMOCOM].license,
  attribution: CATALOGS[SOURCE.OSMOCOM].attribution,
});
const LIMITATIONS = Object.freeze([
  'Free catalogs are incomplete: many recent and India-only models are still missing.',
  'Only brand and model are provided. RAM, storage and colour must still be entered by the shop.',
  'One TAC can cover several variants; names may be model codes (e.g. SM-A515F) instead of marketing names.',
  'Entries are crowd-sourced and not verified by GSMA. Always check the phone itself before buying.',
  'Sync never deletes rows and never overwrites details learned from your own purchases.',
  'The extended catalog is third-party community data (MIT): a TAC can map to an old or overseas variant.',
  'Chipset, bands and release year from the extended file are not synced — this app only needs brand + model.',
]);
const STALE_RUN_MS = 15 * 60 * 1000;
const FIELD_MAX = 255;
const TACDB_MODEL_MAX = 160;

// RFC 4180-style CSV parser: quoted fields, escaped quotes (""), newlines inside
// quotes and CRLF. With `onRow` each row is streamed out and not accumulated, so
// the ~12 MB extended catalog does not need a second copy of every row in memory.
function parseCsv(text, onRow) {
  const rows = onRow ? null : [];
  let row = [], field = '', quoted = false;
  const emit = () => {
    const done = row;
    row = []; field = '';
    if (onRow) onRow(done); else rows.push(done);
  };
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
      row.push(field); emit();
    } else field += ch;
  }
  if (field !== '' || row.length) { row.push(field); emit(); }
  return rows;
}

const clean = v => {
  if (v == null) return null;
  const s = String(v).replace(/\s+/g, ' ').trim();
  return s ? s.slice(0, FIELD_MAX) : null;
};

const sameText = (a, b) => Boolean(a) && Boolean(b) && a.trim().toLowerCase() === b.trim().toLowerCase();
const norm = s => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');

// Manufacturer words (not series names like Redmi/Poco/Realme): they duplicate the
// brand column, so they are dropped from the model text. A leading series name is
// only dropped when it is literally the brand of that row.
const MANUFACTURER_WORDS = new Set(['xiaomi', 'samsung', 'apple', 'huawei', 'motorola', 'nokia', 'sony',
  'sonyericsson', 'zte', 'tcl', 'alcatel', 'htc', 'asus', 'lenovo', 'google', 'nothing', 'honor', 'tecno',
  'infinix', 'itel', 'lava', 'micromax', 'gionee', 'karbonn', 'wiko', 'meizu', 'blackberry', 'sharp',
  'panasonic', 'philips', 'sagem', 'siemens', 'ericsson', 'coolpad', 'energizer', 'ulefone', 'doogee',
  'oukitel', 'umidigi', 'cubot', 'blu', 'sierra', 'ctc', 'old_phones']);

// Drops leading brand/manufacturer words: `XIAOMI REDMI 15C` (brand XIAOMI) keeps
// `REDMI 15C`, while `ITEL A70` (brand ITEL) becomes `A70` so the app never shows
// "ITEL ITEL A70". The last remaining word is never removed.
function trimBrandWords(text, brand) {
  const tokens = String(text || '').split(' ').filter(Boolean);
  while (tokens.length > 1 && (MANUFACTURER_WORDS.has(tokens[0].toLowerCase()) || sameText(tokens[0], brand)))
    tokens.shift();
  return tokens.join(' ');
}

// The 2nd SPECS part is the internal model code (`Xiaomi 2406ERN9CI`,
// `SM-A556B2024`, `Chongqing RMX38532024`). It is kept in brackets when it adds
// information, because Indian boxes print exactly that code.
function codeFromSpecs(part, brand, name) {
  if (!part) return null;
  let tokens = trimBrandWords(part, brand).split(' ').filter(Boolean);
  // `Chongqing RMX38532024`: skip leading words that carry no digits at all.
  const firstCodeWord = tokens.findIndex(t => /\d/.test(t));
  if (firstCodeWord > 0) tokens = tokens.slice(firstCodeWord);
  let code = tokens.join(' ');
  // The dataset glues the release year onto the code: SM-A556B2024 -> SM-A556B.
  // Only when a real code part is left (never turns CPH1901 into CPH).
  const glued = code.match(/^(.*[A-Za-z].*?)((?:19|20)\d\d)$/);
  if (glued && glued[1].length >= 2 && /\d/.test(glued[1])) code = glued[1].trim();
  if (!code || sameText(code, name)) return null;
  // `GALAXY S4 LTE` + `S4 LTE2013`, or a code already contained in the name.
  const n = norm(code);
  if (!n || n.length < 3 || norm(name).includes(n)) return null;
  return code;
}

// Extended catalog: `Brand,TAC,SPECS`, where the quoted SPECS field is a comma
// separated list like `XIAOMI REDMI 15C, Xiaomi 25078RA3EY2025` or
// `POCO C75, Xiaomi 2410FPCC5I, Poco M7 (India Model), 2024, MT D 6020`.
// Brand + model are what this app needs; region/year/chipset parts are ignored.
function modelFromSpecs(brand, specs) {
  const parts = String(specs == null ? '' : specs).split(',')
    .map(s => s.replace(/\s+/g, ' ').trim()).filter(Boolean);
  if (!parts.length) return null;
  const b = (brand || '').trim();
  let name = parts[0];
  let code = parts[1] || null;
  // Rows like `ITEL, ITEL A70`: the first part is only the brand.
  if (sameText(name, b) && code) { name = code; code = null; }
  name = trimBrandWords(name, b);
  const suffix = codeFromSpecs(code, b, name);
  const model = [name, suffix && `(${suffix})`].filter(Boolean).join(' ');
  return model ? model.slice(0, TACDB_MODEL_MAX) : null;
}

// Returns { format, rows: [{tac, brand, model, ram, storage}], invalid, duplicates }.
// Supported: Osmocom export (banner + `tac,name,name,...`), CSV with a header
// row (tac,brand,model,ram,storage in any order), or header-less positional rows.
function parseTacCsv(text) {
  const all = parseCsv(String(text || '').replace(/^\uFEFF/, ''));
  // Extended export (`Brand,TAC,SPECS`): an admin may upload it by hand as well.
  if (all.slice(0, 3).some(c => /^brand$/i.test((c[0] || '').trim()) && /^tac$/i.test((c[1] || '').trim())))
    return parseTacdbCsv(text);
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

// Extended catalog (`Brand,TAC,SPECS`, header row optional). Streams the file so
// peak memory stays at one row at a time, and only brand + model are kept.
function parseTacdbCsv(text) {
  const out = new Map();
  let invalid = 0, duplicates = 0, header = false;
  const onRow = cells => {
    const c = cells.map(x => x.trim());
    if (c.length === 1 && !c[0]) return; // blank line
    if (!header && /^brand$/i.test(c[0]) && /^tac$/i.test(c[1] || '')) { header = true; return; }
    const tac = (c[1] || '').trim();
    const brand = clean(c[0]);
    const model = modelFromSpecs(brand, c[2]);
    if (!/^\d{8}$/.test(tac) || (!brand && !model)) { invalid++; return; }
    if (out.has(tac)) { duplicates++; return; } // first entry wins, deterministic
    out.set(tac, { tac, brand, model: model || null, ram: null, storage: null });
  };
  parseCsv(String(text || '').replace(/^\uFEFF/, ''), onRow);
  return { format: 'tacdb', rows: [...out.values()], invalid, duplicates };
}

// ISO strings sort/compare correctly in SQLite and are cast by PostgreSQL.
const now = () => new Date().toISOString();
const chunks = (arr, n) => Array.from({ length: Math.ceil(arr.length / n) }, (_, i) => arr.slice(i * n, i * n + n));

// Community rows: insert new TACs, refresh rows that came from a sync of this
// catalog (or an accepted `refreshFrom` catalog), protect everything else.
// Lookups happen in batches so a ~250k row file never loads the whole catalog.
async function applyCommunityRows(rows, trxOrDb = db, source = SOURCE.OSMOCOM, refreshFrom = []) {
  const refreshable = new Set([source, ...refreshFrom]);
  const inserts = [];
  let inserted = 0, unchanged = 0, protectedRows = 0, updated = 0;
  const flush = async () => {
    while (inserts.length) await trxOrDb('tac_models').insert(inserts.splice(0, 500));
  };
  for (const part of chunks(rows, 1000)) {
    const existing = new Map((await trxOrDb('tac_models').whereIn('tac', part.map(r => r.tac))
      .select('tac', 'brand', 'model', 'source')).map(r => [r.tac, r]));
    for (const r of part) {
      const old = existing.get(r.tac);
      if (!old) {
        inserts.push({ tac: r.tac, brand: r.brand, model: r.model, source, updated_at: now() });
        inserted++;
      } else if (!refreshable.has(old.source)) protectedRows++;
      else if ((old.brand || null) !== (r.brand || null) || (old.model || null) !== (r.model || null)) {
        await trxOrDb('tac_models').where({ tac: r.tac }).update({ brand: r.brand, model: r.model, source, updated_at: now() });
        updated++;
      } else unchanged++;
    }
    await flush();
  }
  await flush();
  return { inserted, updated, unchanged, protected: protectedRows };
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

async function downloadOne(url, { timeoutMs, maxBytes, fetchImpl = fetch }) {
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
  return { text: new TextDecoder('utf-8').decode(Buffer.concat(parts)), bytes: size, url };
}

// Tries each mirror in order (the extended catalog has a GitHub + a CDN URL) and
// returns the first response that works: { text, bytes, url }.
async function downloadText(urls, opts) {
  const list = (Array.isArray(urls) ? urls : [urls]).filter(Boolean);
  let lastError = null;
  for (const url of list) {
    try {
      return await downloadOne(url, opts);
    } catch (err) {
      lastError = err;
      if (err?.name === 'TimeoutError') lastError = new Error(`Upstream timed out after ${opts.timeoutMs} ms`);
    }
  }
  throw lastError || new Error('No catalog URL configured');
}

function catalog(source) { return CATALOGS[source] || null; }

// Per-catalog settings; env overrides win over the defaults.
function catalogConfig(source) {
  const def = CATALOGS[source];
  if (!def) return null;
  const envUrls = (process.env[def.env.urls] || '').split(/[\s,]+/).filter(Boolean);
  const minRows = process.env[def.env.minRows];
  return {
    source,
    urls: envUrls.length ? envUrls : def.defaultUrls,
    timeoutMs: Number(process.env[def.env.timeout]) || def.defaults.timeoutMs,
    maxBytes: (Number(process.env[def.env.maxMB]) || def.defaults.maxMb) * 1024 * 1024,
    minRows: minRows !== undefined && minRows !== '' ? Number(minRows) : def.defaults.minRows,
  };
}

const runIdOf = row => (typeof row === 'object' ? row.id : row);
let activeRun = null; // in-process lock: one sync at a time (Render runs one instance by default)

async function runSync(runId, source, opts) {
  const def = CATALOGS[source];
  const cfg = { ...catalogConfig(source), ...opts };
  const refreshFrom = source === SOURCE.TACDB && process.env.TAC_SYNC_TACDB_REFRESH_OSMOCOM === 'true'
    ? [SOURCE.OSMOCOM] : def.refreshFrom;
  try {
    const { text, bytes, url } = await downloadText(cfg.urls, cfg);
    const parsed = def.format === 'tacdb' ? parseTacdbCsv(text) : parseTacCsv(text);
    // Guard against HTML error pages / truncated or garbage responses.
    if (parsed.rows.length < cfg.minRows)
      throw new Error(`Upstream returned only ${parsed.rows.length} valid TAC rows (expected at least ${cfg.minRows}); nothing changed`);
    const result = await db.transaction(trx => applyCommunityRows(parsed.rows, trx, source, refreshFrom));
    await db('tac_sync_runs').where({ id: runId }).update({
      status: 'success', finished_at: now(), url: String(url).slice(0, 500), bytes, rows_seen: parsed.rows.length,
      invalid: parsed.invalid + parsed.duplicates, inserted: result.inserted, updated: result.updated,
      unchanged: result.unchanged, protected: result.protected,
    });
  } catch (err) {
    const message = err?.name === 'TimeoutError' ? `Upstream timed out after ${cfg.timeoutMs} ms` : String(err?.message || err);
    await db('tac_sync_runs').where({ id: runId }).update({ status: 'failed', finished_at: now(), error: message.slice(0, 1000) })
      .catch(e => console.error('TAC sync status update failed:', e));
  }
}

// Starts a background sync of one catalog. Returns { started, run }
// (started=false while another sync of any catalog is running).
async function startSync({ userId = null, source = SOURCE.OSMOCOM, ...opts } = {}) {
  if (!CATALOGS[source]) throw new Error(`Unknown TAC catalog '${source}'`);
  if (activeRun) return { started: false, run: await db('tac_sync_runs').where({ id: activeRun.id }).first() };
  const staleBefore = new Date(Date.now() - STALE_RUN_MS).toISOString();
  // Rows left "running" by a crash/restart are marked failed so they don't block forever.
  await db('tac_sync_runs').where({ status: 'running' }).andWhere('started_at', '<', staleBefore)
    .update({ status: 'failed', finished_at: now(), error: 'Interrupted (server restarted or timed out)' });
  const running = await db('tac_sync_runs').where({ status: 'running' }).first();
  if (running) return { started: false, run: running };
  const cfg = { ...catalogConfig(source), ...opts };
  const [row] = await db('tac_sync_runs').insert({
    source, url: String(cfg.urls?.[0] || '').slice(0, 500), status: 'running', started_at: now(), started_by: userId,
  }).returning('id');
  const id = runIdOf(row);
  const promise = runSync(id, source, opts).finally(() => { if (activeRun?.id === id) activeRun = null; });
  activeRun = { id, source, promise };
  return { started: true, run: await db('tac_sync_runs').where({ id }).first(), promise };
}

async function status() {
  const bySource = await db('tac_models').select('source').count('* as n').groupBy('source');
  const counts = Object.fromEntries(bySource.map(r => [r.source || SOURCE.LEGACY, Number(r.n)]));
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  const recent = await db('tac_sync_runs').orderBy('id', 'desc').limit(5);
  const lastSuccess = await db('tac_sync_runs').where({ status: 'success' }).orderBy('id', 'desc').first();
  let externalApi = { enabled: false, url: null };
  try {
    const api = require('./tacApi');
    externalApi = { enabled: api.enabled(), url: api.config().url || null };
  } catch { /* optional module */ }

  const catalogs = [];
  for (const source of CATALOG_KEYS) {
    const def = CATALOGS[source];
    const cfg = catalogConfig(source);
    const lastForSource = recent.find(r => r.source === source) || null;
    catalogs.push({
      source, label: def.label, short: def.short, note: def.note, syncable: true,
      enabled: Boolean(cfg.urls.length), url: cfg.urls[0] || null,
      min_rows: cfg.minRows, homepage: def.homepage, license: def.license, attribution: def.attribution,
      count: counts[source] || 0, last_run: lastForSource,
      last_success: await db('tac_sync_runs').where({ status: 'success', source }).orderBy('id', 'desc').first() || null,
    });
  }
  return {
    total, counts, catalogs,
    local: [
      { source: SOURCE.LEARNED, label: 'Learned from shop purchases', count: counts[SOURCE.LEARNED] || 0 },
      { source: SOURCE.CSV, label: 'Admin CSV import', count: counts[SOURCE.CSV] || 0 },
      { source: SOURCE.API, label: 'External TAC API (optional)', count: counts[SOURCE.API] || 0, enabled: externalApi.enabled },
      { source: 'older', label: 'Older / sample entries', count: (counts[SOURCE.LEGACY] || 0) + (counts[SOURCE.SEED] || 0) },
    ],
    running: recent.find(r => r.status === 'running') || null,
    last_run: recent[0] || null, last_success: lastSuccess || null, recent,
    licenses: CATALOG_KEYS.map(s => ({ name: CATALOGS[s].label, homepage: CATALOGS[s].homepage,
      license: CATALOGS[s].license, attribution: CATALOGS[s].attribution })),
    external_api: externalApi,
    // Kept for older app builds that read a single catalog block.
    catalog: { ...CATALOG_INFO, url: catalogConfig(SOURCE.OSMOCOM).urls[0] },
    limitations: LIMITATIONS,
  };
}

module.exports = {
  DEFAULT_URL: CATALOGS[SOURCE.OSMOCOM].defaultUrls[0], SOURCE, CATALOGS, CATALOG_KEYS, CATALOG_INFO, LIMITATIONS,
  catalog, catalogConfig, modelFromSpecs,
  parseCsv, parseTacCsv, parseTacdbCsv, applyCommunityRows, applyAdminRows, downloadText, startSync, status,
  _activeRun: () => activeRun,
};
