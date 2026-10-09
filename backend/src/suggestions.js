// RAM / storage / colour suggestions for the Buy form.
//
// Everything here is built from THIS app's own data (the shared `tac_models`
// catalog, which is filled in by real purchases and CSV imports). No external
// API is called and no IMEI ever leaves the server, so this costs nothing and
// the dropdowns match the wording the shop already uses.
//
// Priority for each list:
//   1. the exact value stored for this TAC (so a known phone re-fills itself)
//   2. values recorded for the same model anywhere in the app
//   3. values recorded for the same brand
//   4. a small static fallback so the dropdown is never empty
const db = require('./db');

const FALLBACK = Object.freeze({
  ram: ['2GB', '3GB', '4GB', '6GB', '8GB', '12GB', '16GB'],
  storage: ['16GB', '32GB', '64GB', '128GB', '256GB', '512GB', '1TB'],
  color: ['Black', 'White', 'Blue', 'Silver', 'Grey', 'Gold', 'Green', 'Purple', 'Red'],
});

const COLUMNS = Object.keys(FALLBACK);
const MAX_OPTIONS = 24;
const MAX_ROWS = 200;

const clean = value => {
  const s = value == null ? '' : String(value).trim();
  return s ? s.slice(0, 64) : null;
};

// Distinct non-empty values of `column`, case-insensitively matched on model/brand.
// `column` is validated against a fixed allow-list so no user input reaches SQL.
async function distinctBy(column, { model, brand } = {}) {
  if (!COLUMNS.includes(column)) return [];
  const q = db('tac_models').whereNotNull(column);
  if (model) q.andWhereRaw('LOWER(model) = ?', [String(model).toLowerCase()]);
  if (brand) q.andWhereRaw('LOWER(brand) = ?', [String(brand).toLowerCase()]);
  // pluck() adds the select column; a bare distinct() avoids listing it twice.
  const rows = await q.distinct().orderBy(column).limit(MAX_ROWS).pluck(column);
  return rows.map(clean).filter(Boolean);
}

async function optionsFor(column, { model, brand, preferred } = {}) {
  const out = [];
  const seen = new Set();
  const add = value => {
    const s = clean(value);
    if (!s) return;
    const key = s.toLowerCase();
    if (seen.has(key)) return; // de-duplicate case-insensitively, keep first spelling
    seen.add(key);
    out.push(s);
  };
  add(preferred);
  if (model) for (const v of await distinctBy(column, { model })) add(v);
  if (brand) for (const v of await distinctBy(column, { brand })) add(v);
  for (const v of FALLBACK[column] || []) add(v);
  return out.slice(0, MAX_OPTIONS);
}

/// Dropdown options for one phone. `tacRow` is the matched `tac_models` row (may be null).
async function options(tacRow) {
  if (!tacRow) return { ram: [...FALLBACK.ram], storage: [...FALLBACK.storage], color: [...FALLBACK.color] };
  const model = clean(tacRow.model), brand = clean(tacRow.brand);
  const [ram, storage, color] = await Promise.all([
    optionsFor('ram', { model, brand, preferred: tacRow.ram }),
    optionsFor('storage', { model, brand, preferred: tacRow.storage }),
    optionsFor('color', { model, brand, preferred: tacRow.color }),
  ]);
  return { ram, storage, color };
}

module.exports = { options, distinctBy, FALLBACK };
