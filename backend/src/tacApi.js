// Optional external TAC lookup, used only when the local catalog misses.
//
// The bundled Osmocom catalog is free but incomplete, and it is weakest exactly
// where a Indian used-phone shop needs it most: recent Redmi / Realme / Vivo /
// Oppo variants. Setting TAC_API_URL lets the server ask a TAC API on a miss.
//
// Two things keep this cheap and safe:
//   * a result is stored in `tac_models` with source 'api', so any single TAC
//     costs at most one request, ever;
//   * the community sync only overwrites rows whose source is 'osmocom', so API
//     rows (like learned/csv/legacy ones) are never clobbered.
// With nothing configured the module is a no-op and no request is ever made.
const db = require('./db');

const SOURCE = 'api';
const FIELD_MAX = 255;

function config() {
  return {
    url: (process.env.TAC_API_URL || '').trim(),
    key: (process.env.TAC_API_KEY || '').trim(),
    method: (process.env.TAC_API_METHOD || 'POST').trim().toUpperCase(),
    timeoutMs: Number(process.env.TAC_API_TIMEOUT_MS) || 4000,
  };
}

const enabled = () => Boolean(config().url);

const clean = value => {
  const s = String(value == null ? '' : value).replace(/\s+/g, ' ').trim();
  return s ? s.slice(0, FIELD_MAX) : null;
};

// Providers return different shapes. Take the first field that carries a value.
function parse(body) {
  if (!body || typeof body !== 'object' || body.found === false) return null;
  const brand = clean(typeof body.brand === 'object' ? body.brand?.name : body.brand)
    || clean(typeof body.manufacturer === 'object' ? body.manufacturer?.name : body.manufacturer);
  const model = clean(body.model) || clean(body.model_name) || clean(body.marketing_name)
    || clean(body.device_name);
  if (!brand && !model) return null;
  return { brand, model };
}

// Inserts only when the TAC is still unknown, so learned / csv / imported rows
// always win and a concurrent request cannot create a duplicate.
async function remember(tac, info) {
  await db('tac_models').insert({
    tac, brand: info.brand, model: info.model, source: SOURCE, updated_at: new Date().toISOString(),
  }).onConflict('tac').ignore();
  return (await db('tac_models').where({ tac }).first()) || { tac, ...info, source: SOURCE };
}

/// Looks a TAC up externally. Returns the stored row, or null on a miss,
/// a disabled provider, or any error — a third party must never break buying.
async function lookup(tac, fetchImpl = fetch) {
  if (!/^\d{8}$/.test(tac)) return null;
  const cfg = config();
  if (!cfg.url) return null;
  // Already known (bought before, imported, or fetched earlier): answer from
  // the local catalog and spend no request. This is what makes the free tier
  // of a provider last, since each TAC costs at most one call, ever.
  const known = await db('tac_models').where({ tac }).first();
  if (known) return known;
  try {
    const url = cfg.url.includes('{tac}') ? cfg.url.replace('{tac}', encodeURIComponent(tac)) : cfg.url;
    const init = {
      method: cfg.method === 'GET' ? 'GET' : 'POST',
      signal: AbortSignal.timeout(cfg.timeoutMs),
      headers: { Accept: 'application/json' },
    };
    if (cfg.key) init.headers['X-Api-Key'] = cfg.key;
    if (init.method === 'POST') {
      init.headers['Content-Type'] = 'application/json';
      init.body = JSON.stringify({ query: tac });
    }
    const res = await fetchImpl(url, init);
    if (!res.ok) return null;
    const info = parse(await res.json());
    return info ? await remember(tac, info) : null;
  } catch {
    return null;
  }
}

module.exports = { SOURCE, config, enabled, parse, remember, lookup };
