// Sirf SUPER ADMIN: shops + unke login manage karna, TAC database import.
//
// Yahan ka rule: Super Admin ko shop ke business data (stock, IMEI, sales,
// profit, payment ledger, customer/ID proof) ka **default access nahi** milta.
// Uske liye pehle ek temporary, reason-logged support session (`support_access`)
// lena padta hai — wo bhi read-only (dekhein routes/shop.js ka guard). Is route
// file se sirf manage karne layak basic details jaati hain: shop name, status,
// login username aur **masked** contact.
const r = require('express').Router();
const bcrypt = require('bcryptjs');
const multer = require('multer');
const db = require('../db');
const { requireAuth, requireRole } = require('../auth');
const { wrap } = require('../util');
const V = require('../validation');
const TAC = require('../tac');
const support = require('../support');
const thumb = require('../thumb');
r.use(requireAuth, requireRole('superadmin'));

// Shop row ka public (admin-app safe) roop: business data ke bina.
function safeShop(shop, access, history) {
  const phone = shop.phone ? String(shop.phone) : null;
  return {
    id: shop.id,
    name: shop.name,
    owner_name: shop.owner_name,
    address: shop.address,
    gst_no: shop.gst_no,
    active: shop.active,
    created_at: shop.created_at,
    // Full number jaan-boojh kar nahi bhejte — `POST /shops/:id/reveal-contact`
    // ek support session ke andar, log me likh kar deta hai.
    phone_masked: support.maskPhone(phone),
    has_phone: !!phone,
    login: shop.login ?? null,
    support: access?.active ?? null,   // { reason, expires_in_ms } ya null
    support_sessions: access?.total ?? 0,
    // Delete sirf khaali shop par. Counts jaan-boojh kar nahi bhejte (business
    // data), sirf permission — history ho to sirf deactivate hota hai.
    can_delete: history === null,
    // Bill logo hai ya nahi. Logo khud (base64) list me nahi jaata — wo bhaari
    // hai — par Edit dialog isi flag se `GET /shops/:id/logo` se preview laata
    // hai, taaki admin ko dikhe ki kaunsa logo upload hua hai.
    has_logo: Boolean(Number(shop.has_logo)),
    // List ke row me chhota logo (96px, ~2 KB). Poora logo kabhi list me nahi.
    logo_thumb: shop.logo_thumb || null,
  };
}

/// Shop logo ko auto-adjust karke `{ logo_data, logo_thumb }` deta hai.
/// Auto-adjust na ho (purana PNG/WebP, corrupt file) to logo jaisa hai waisa hi
/// rehta hai aur thumbnail khaali — list me icon dikhti hai, kuch toota nahi.
function normalizedLogo(logoData) {
  if (!logoData) return { logo_data: logoData === '' ? null : logoData, logo_thumb: null };
  let tiles = null;
  try { tiles = thumb.shopLogoTiles(logoData); } catch { tiles = null; }
  return tiles ? { logo_data: tiles.logo, logo_thumb: tiles.thumb }
    : { logo_data: logoData, logo_thumb: null };
}

// Wo tables jinme shop ka itihaas rehta hai — inme ek bhi row ho to shop delete
// nahi hota, sirf deactivate. (users/shop_phones/sale_payments to cascade me hi
// delete hote hain, unhe ginti me nahi lete.)
const HISTORY_TABLES = ['phones', 'sales', 'support_access'];

/// Jin shops ke paas koi bhi history row hai, unke ids ek hi round-trip me.
async function shopsWithHistory() {
  const ids = new Set();
  for (const table of HISTORY_TABLES) {
    const rows = await db(table).distinct('shop_id');
    for (const row of rows) if (row.shop_id != null) ids.add(Number(row.shop_id));
  }
  return ids;
}

/// Ek shop ke liye wahi check — delete route par.
async function hasHistory(shopId) {
  for (const table of HISTORY_TABLES) {
    const row = await db(table).where({ shop_id: shopId }).first();
    if (row) return true;
  }
  return false;
}

r.get('/dashboard', wrap(async (req, res) => {
  // Sirf operational counts. Shop ka stock/sales/profit yahan bhi nahi.
  const shops = await db('shops').select('active');
  const active = shops.filter(s => s.active === true || s.active === 1).length;
  const open = await db('support_access').whereNull('ended_at_ms').andWhere('expires_at_ms', '>', Date.now()).count('* as c').first();
  res.json({
    shops: shops.length,
    active_shops: active,
    inactive_shops: shops.length - active,
    support_active: +open.c || 0,
  });
}));

r.get('/shops', wrap(async (req, res) => {
  // Pehle poora row (base64 `logo_data` ke saath) padha jaata tha aur response me
  // se hata diya jaata tha — har shop ka logo bina zaroorat DB se aata tha.
  // Ab sirf wahi columns jo list dikhati hai, aur ek `has_logo` flag.
  const shops = await db('shops')
    .select('id', 'name', 'owner_name', 'address', 'gst_no', 'active', 'created_at', 'phone', 'logo_thumb')
    .select(db.raw("case when logo_data is null or logo_data = '' then 0 else 1 end as has_logo"))
    .orderBy('id', 'desc');
  const access = await support.summaryByShop();
  // Ek query sab logins ke liye (pehle har shop par alag query chalti thi).
  const logins = await db('users').where({ role: 'shop_admin' }).select('id', 'shop_id', 'username', 'active');
  const byShop = new Map(logins.map(u => [Number(u.shop_id), u]));
  const withHistory = await shopsWithHistory();
  res.json(shops.map(s => {
    s.login = byShop.get(Number(s.id)) ?? null;
    return safeShop(s, access.get(Number(s.id)), withHistory.has(Number(s.id)) ? true : null);
  }));
}));

// Nayi shop + uska login ek saath
r.post('/shops', wrap(async (req, res) => {
  const b = V.body(req);
  const data = V.shopData(b);
  // Naya logo aaya to use yahin auto-adjust kar dete hain: 512px square tile
  // (margin trim + centre) + 128px list thumbnail. Isse PDF, Profile aur list —
  // teeno me logo ek hi tarah "set" dikhta hai, chahe image kisi bhi shape ki ho.
  if (Object.hasOwn(data, 'logo_data')) Object.assign(data, normalizedLogo(data.logo_data));
  const username = V.text(b.username, 'username', { required: true, max: 64 });
  if (!/^[A-Za-z0-9._-]{3,64}$/.test(username))
    return res.status(400).json({ error: 'username must be 3-64 letters, numbers, dot, underscore or hyphen' });
  const password = V.password(b.password);
  if (await db('users').where({ username }).first()) return res.status(409).json({ error: 'Username pehle se hai' });
  const id = await db.transaction(async trx => {
    const [row] = await trx('shops').insert(data).returning('id');
    const shopId = typeof row === 'object' ? row.id : row;
    await trx('users').insert({ username, name: data.owner_name || data.name, role: 'shop_admin', shop_id: shopId,
      password_hash: bcrypt.hashSync(password, 10), token_version: 0 });
    return shopId;
  });
  res.json({ id });
}));

r.put('/shops/:id', wrap(async (req, res) => {
  const id = V.id(req.params.id, 'shop id');
  const data = V.shopData(V.body(req), true);
  // logo_data aaya (naya ya khaali = hataya) to auto-adjust + thumbnail saath —
  // warna list/PDF me purana logo dikhta rehta.
  if (Object.hasOwn(data, 'logo_data')) Object.assign(data, normalizedLogo(data.logo_data));
  const changed = await db('shops').where({ id }).update(data);
  if (!changed) return res.status(404).json({ error: 'Shop nahi mila' });
  res.json({ ok: true });
}));

// Edit dialog ka bill-logo preview. List me logo nahi jaata (bhaari base64),
// isliye admin jab ek shop ka "Edit details" kholta hai tab sirf usi ka logo
// maangta hai — "kaunsa logo upload hua hai" ka jawab.
r.get('/shops/:id/logo', wrap(async (req, res) => {
  const id = V.id(req.params.id, 'shop id');
  const shop = await db('shops').where({ id }).first('id', 'logo_data', 'logo_thumb');
  if (!shop) return res.status(404).json({ error: 'Shop nahi mila' });
  // logo_thumb (128px full-bleed tile) preview ke liye — wahi roop jo list/Home
  // me dikhta hai (box poora bhara, koi patti nahi).
  res.json({ shop_id: shop.id, logo_data: shop.logo_data || null, logo_thumb: shop.logo_thumb || null });
}));

r.post('/shops/:id/reset-password', wrap(async (req, res) => {
  const shopId = V.id(req.params.id, 'shop id');
  const b = V.body(req);
  const password = V.password(b.password);
  const changed = await db('users').where({ shop_id: shopId, role: 'shop_admin' }).update({
    password_hash: bcrypt.hashSync(password, 10),
    token_version: db.raw('?? + 1', ['token_version']),
  });
  if (!changed) return res.status(404).json({ error: 'Shop owner login nahi mila' });
  res.json({ ok: true, sessions_revoked: true });
}));

r.delete('/shops/:id', wrap(async (req, res) => {
  const shopId = V.id(req.params.id, 'shop id');
  const exists = await db('shops').where({ id: shopId }).first();
  if (!exists) return res.status(404).json({ error: 'Shop nahi mila' });
  // History (stock / sales / payments) aur support-access log — jo shop owner ko
  // dikhta hai — delete se hamesha ke liye na mite. Aisi shop sirf deactivate hoti hai.
  if (await hasHistory(shopId)) {
    return res.status(409).json({
      error: 'This shop has stock, sales or support history, so it cannot be deleted. Deactivate it instead.',
      code: 'shop_has_history',
    });
  }
  await db.transaction(async trx => {
    await trx('support_access').where({ shop_id: shopId }).del();
    await trx('sale_payments').where({ shop_id: shopId }).del();
    await trx('sales').where({ shop_id: shopId }).del();
    await trx('phones').where({ shop_id: shopId }).del();
    await trx('users').where({ shop_id: shopId }).del();
    await trx('shops').where({ id: shopId }).del();
  });
  res.json({ ok: true });
}));

// ---------- TEMPORARY SUPPORT ACCESS ----------
// Session shuru karna. Reason zaroori hai, time limit chhoti rakhein.
r.post('/shops/:id/support-access', wrap(async (req, res) => {
  const shopId = V.id(req.params.id, 'shop id');
  const shop = await db('shops').where({ id: shopId }).first();
  if (!shop) return res.status(404).json({ error: 'Shop nahi mila' });
  const b = V.body(req);
  const session = await support.start({ shopId, userId: req.user.id, reason: b.reason, minutes: b.minutes });
  res.status(201).json({ session });
}));

// Session khatam karna (shop khatam kar de ya admin).
r.delete('/shops/:id/support-access', wrap(async (req, res) => {
  const shopId = V.id(req.params.id, 'shop id');
  const running = await support.activeGrant(shopId);
  if (!running) return res.status(404).json({ error: 'Koi support session chal nahi raha' });
  await support.end(running.id, req.user.id, 'admin_ended');
  res.json({ ok: true, ended: true });
}));

// Access log: kaun, kis shop ka, kab, kyun, kitna dekha gaya.
r.get('/support-access', wrap(async (req, res) => {
  const shopId = req.query.shop_id == null || req.query.shop_id === '' ? null : V.id(req.query.shop_id, 'shop_id');
  res.json({ items: await support.list({ shopId, limit: req.query.limit }) });
}));

// Masked contact kholna: sirf chalu support session me, aur log me likh kar.
r.post('/shops/:id/reveal-contact', wrap(async (req, res) => {
  const shopId = V.id(req.params.id, 'shop id');
  const shop = await db('shops').where({ id: shopId }).first();
  if (!shop) return res.status(404).json({ error: 'Shop nahi mila' });
  const running = await support.activeGrant(shopId);
  if (!running)
    return res.status(403).json({ error: 'Poora number dekhne ke liye pehle support access shuru karein — reason aur time limit ke saath.',
      code: 'support_access_required' });
  const logged = await support.logReveal(running);
  res.json({ phone: shop.phone, owner_name: shop.owner_name, contact_reveals: logged.contact_reveals });
}));

// TAC CSV import. Accepts `tac,brand,model[,ram,storage]` (admin data, may overwrite
// those columns) or the raw Osmocom export (treated exactly like the sync:
// additive, never overwrites learned/admin rows, brand+model only).
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 50 * 1024 * 1024 } });
r.post('/tac/import', upload.single('file'), wrap(async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'CSV file bhejein' });
  const parsed = TAC.parseTacCsv(req.file.buffer.toString('utf8'));
  if (!parsed.rows.length) return res.status(400).json({ error: 'CSV me koi valid TAC row nahi mili', invalid: parsed.invalid });
  const result = await db.transaction(trx => parsed.format === 'osmocom' ? TAC.applyCommunityRows(parsed.rows, trx)
    : parsed.format === 'tacdb' ? TAC.applyCommunityRows(parsed.rows, trx, TAC.SOURCE.TACDB)
      : TAC.applyAdminRows(parsed.rows, trx));
  res.json({ imported: parsed.rows.length, format: parsed.format, invalid: parsed.invalid, duplicates: parsed.duplicates, ...result });
}));

// Free TAC catalogs (Osmocom community + extended India-models list) sync.
// Runs in the background; poll /tac/status. `/tac/sync` keeps syncing the default
// Osmocom catalog so older app builds keep working; `/tac/sync/:source` picks one.
r.get('/tac/status', wrap(async (req, res) => res.json(await TAC.status())));
async function startTacSync(req, res) {
  const source = req.params.source || TAC.SOURCE.OSMOCOM;
  if (!TAC.catalog(source))
    return res.status(404).json({ error: `Unknown TAC catalog '${source}'`, catalogs: TAC.CATALOG_KEYS });
  const { started, run } = await TAC.startSync({ userId: req.user.id, source });
  res.status(started ? 202 : 409).json({
    started, run,
    ...(started ? {} : { error: `TAC sync pehle se chal raha hai (${run?.source || source})` }),
  });
}
r.post('/tac/sync', wrap(startTacSync));
r.post('/tac/sync/:source', wrap(startTacSync));
module.exports = r;
