// Shop ka kaam: IMEI lookup, Buy, Stock, Sell, Reports
const r = require('express').Router();
const db = require('../db');
const { requireAuth } = require('../auth');
const { validImei, today, wrap } = require('../util');
const V = require('../validation');
const suggestions = require('../suggestions');
const tacApi = require('../tacApi');
r.use(requireAuth);

// Columns returned by list endpoints. `customer_id_photo` is deliberately left
// out: it holds a base64 image and would bloat every stock/reports response.
// The full row (photo included) is available from GET /phones/:id.
const PHONE_LIST_COLUMNS = ['id', 'shop_id', 'imei', 'imei2', 'serial_number', 'brand', 'model', 'ram', 'storage',
  'color', 'condition', 'accessories', 'buy_price', 'buy_date', 'seller_name', 'seller_phone', 'seller_id_type',
  'seller_id_no', 'seller_address', 'notes', 'status', 'created_by', 'created_at'];

// shop_id nikalna: shop user -> apni shop; superadmin -> ?shop_id
function shopId(req) {
  if (req.user.role === 'superadmin') {
    const raw = req.query?.shop_id ?? req.body?.shop_id;
    if (raw == null || raw === '') return null;
    try { return V.id(raw, 'shop_id'); } catch { return null; }
  }
  return req.user.shop_id;
}
function needShop(req, res) {
  const id = shopId(req);
  if (!id) { res.status(400).json({ error: 'shop_id required' }); return null; }
  return id;
}
function isUniqueViolation(err) {
  return err?.code === '23505' || err?.code === 'SQLITE_CONSTRAINT_UNIQUE' ||
    err?.code === 'SQLITE_CONSTRAINT_PRIMARYKEY' || /unique constraint failed/i.test(err?.message || '');
}

// ---------- IMEI LOOKUP ----------
r.get('/imei/:imei', wrap(async (req, res) => {
  const imei = req.params.imei.trim();
  const valid = validImei(imei);
  const tac = imei.slice(0, 8);
  // Local catalog first (free, instant). Only on a miss, and only if the
  // deployment configured one, ask an external TAC API and cache the answer.
  let info = await db('tac_models').where({ tac }).first();
  if (!info && valid && tacApi.enabled()) info = await tacApi.lookup(tac);
  const sid = shopId(req);
  const inStock = sid ? await db('phones').where({ shop_id: sid, status: 'in_stock' })
    .andWhere(q => q.where({ imei }).orWhere({ imei2: imei })).first() : null;
  // Same column list as /stock: history rows must not carry the base64 ID photo.
  const history = sid ? await db('phones').select(PHONE_LIST_COLUMNS).where({ shop_id: sid })
    .andWhere(q => q.where({ imei }).orWhere({ imei2: imei })).orderBy('id', 'desc') : [];
  // Brand + model come from the local TAC catalog (free, no external call).
  // ram/storage/color cannot be derived from an IMEI, so we send the values this
  // app has already recorded for that model/brand and let the shop pick one.
  const options = await suggestions.options(info);
  res.json({ imei, valid, tac, found: !!info, info: info || null, options, already_in_stock: !!inStock, history });
}));

// ---------- BUY (stock me add) ----------
r.post('/buy', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const b = V.body(req);
  const buyFields = ['imei', 'imei2', 'serial_number', 'brand', 'model', 'ram', 'storage', 'color', 'condition', 'accessories',
    'buy_price', 'buy_date', 'seller_name', 'seller_phone', 'seller_id_type', 'seller_id_no', 'seller_address', 'notes',
    'customer_id_photo'];
  if (Object.keys(b).some(k => !buyFields.includes(k))) return res.status(400).json({ error: 'Unsupported purchase field' });
  const fields = V.phoneData(b);
  const id = await db.transaction(async trx => {
    const identifiers = [fields.imei, fields.imei2].filter(Boolean);
    const duplicate = await trx('phones').where({ shop_id: sid, status: 'in_stock' }).andWhere(q => {
      identifiers.forEach(value => q.where('imei', value).orWhere('imei2', value));
    }).first();
    if (duplicate) V.fail('Ye IMEI/IMEI2 pehle se stock me hai');
    const row = {
      ...fields, shop_id: sid, created_by: req.user.id, status: 'in_stock',
    };
    const [ins] = await trx('phones').insert(row).returning('id');
    // App learns a TAC only after the inventory insert is safely in the same transaction.
    await trx('tac_models').insert({ tac: fields.imei.slice(0, 8), brand: fields.brand, model: fields.model,
      ram: fields.ram, storage: fields.storage, color: fields.color, source: 'learned',
      updated_at: new Date().toISOString() }).onConflict('tac').merge();
    return typeof ins === 'object' ? ins.id : ins;
  });
  res.json({ id });
}));

// ---------- STOCK ----------
r.get('/stock', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const status = req.query.status || 'in_stock';
  if (!['in_stock', 'sold'].includes(status)) return res.status(400).json({ error: 'status invalid' });
  if (req.query.search != null && (typeof req.query.search !== 'string' || req.query.search.length > 100))
    return res.status(400).json({ error: 'search invalid' });
  const q = db('phones').where({ shop_id: sid, status });
  if (req.query.search) {
    const s = `%${req.query.search}%`;
    q.andWhere(w => w.where('imei', 'like', s).orWhere('imei2', 'like', s).orWhere('model', 'like', s).orWhere('brand', 'like', s));
  }
  res.json(await q.select(PHONE_LIST_COLUMNS).orderBy('id', 'desc'));
}));

r.get('/phones/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'phone id');
  const p = await db('phones').where({ id, shop_id: sid }).first();
  if (!p) return res.status(404).json({ error: 'Nahi mila' });
  p.sale = await db('sales').where({ phone_id: p.id, shop_id: sid }).first() || null;
  res.json(p);
}));

r.put('/phones/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'phone id');
  const b = V.body(req);
  const allowed = ['brand', 'model', 'ram', 'storage', 'color', 'condition', 'accessories', 'buy_price', 'buy_date',
    'seller_name', 'seller_phone', 'seller_id_type', 'seller_id_no', 'seller_address', 'notes', 'imei2',
    'serial_number', 'customer_id_photo'];
  if (Object.keys(b).some(k => !allowed.includes(k))) return res.status(400).json({ error: 'Unsupported phone field' });
  const upd = V.phoneData(b, true);
  if (Object.hasOwn(upd, 'imei2') && upd.imei2) {
    if (await db('phones').where({ id, shop_id: sid }).andWhere(q => q.where({ imei: upd.imei2 }).orWhere({ imei2: upd.imei2 })).first())
      return res.status(400).json({ error: 'IMEI2 must differ from this phone IMEI' });
    const duplicate = await db('phones').where({ shop_id: sid, status: 'in_stock' }).whereNot({ id })
      .andWhere(q => q.where({ imei: upd.imei2 }).orWhere({ imei2: upd.imei2 })).first();
    if (duplicate) return res.status(409).json({ error: 'IMEI2 already belongs to another in-stock phone' });
  }
  const changed = await db('phones').where({ id, shop_id: sid }).update(upd);
  if (!changed) return res.status(404).json({ error: 'Nahi mila' });
  res.json({ ok: true });
}));

r.delete('/phones/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'phone id');
  const n = await db('phones').where({ id, shop_id: sid, status: 'in_stock' }).del();
  if (!n) return res.status(404).json({ error: 'In-stock phone nahi mila' });
  res.json({ ok: true });
}));

// ---------- SELL ----------
r.post('/sell', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const sale = V.saleData(V.body(req));
  try {
    const id = await db.transaction(async trx => {
      // PostgreSQL row lock serializes competing sales. Conditional update and
      // unique sales.phone_id index are defense in depth for every supported DB.
      const p = await trx('phones').where({ id: sale.phone_id, shop_id: sid, status: 'in_stock' }).forUpdate().first();
      if (!p) throw Object.assign(new Error('Phone stock me nahi hai ya pehle hi sell ho chuka hai'), { status: 409 });
      const boughtOn = p.buy_date instanceof Date ? p.buy_date.toISOString().slice(0, 10) : String(p.buy_date).slice(0, 10);
      if (sale.sell_date < boughtOn) V.fail('Sell date buy date se pehle nahi ho sakti');
      const changed = await trx('phones').where({ id: p.id, shop_id: sid, status: 'in_stock' }).update({ status: 'sold' });
      if (changed !== 1) throw Object.assign(new Error('Phone already sold; stock refresh karein'), { status: 409 });
      const [ins] = await trx('sales').insert({
        ...sale, shop_id: sid, buy_price_at_sale: p.buy_price, created_by: req.user.id,
      }).returning('id');
      return typeof ins === 'object' ? ins.id : ins;
    });
    res.json({ id });
  } catch (err) {
    if (isUniqueViolation(err) || ['SQLITE_BUSY', 'SQLITE_LOCKED'].includes(err?.code))
      return res.status(409).json({ error: 'Phone already has a sale or is being sold; stock refresh karein' });
    throw err;
  }
}));

r.get('/sales', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const { from, to } = V.range(req.query, ['1900-01-01', '2999-12-31']);
  res.json(await db('sales as s').join('phones as p', 'p.id', 's.phone_id')
    .where('s.shop_id', sid).whereBetween('s.sell_date', [from, to])
    .select('s.*', 'p.imei', 'p.brand', 'p.model', 'p.ram', 'p.storage')
    .select(db.raw('COALESCE(??, ??) as ??', ['s.buy_price_at_sale', 'p.buy_price', 'buy_price']))
    .orderBy('s.id', 'desc'));
}));

// Sale cancel -> phone wapas stock me
r.delete('/sales/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const saleId = V.id(req.params.id, 'sale id');
  const cancelled = await db.transaction(async trx => {
    const s = await trx('sales').where({ id: saleId, shop_id: sid }).forUpdate().first();
    if (!s) return false;
    const restored = await trx('phones').where({ id: s.phone_id, shop_id: sid, status: 'sold' }).update({ status: 'in_stock' });
    if (restored !== 1) throw Object.assign(new Error('Sale/device state mismatch; contact support'), { status: 409 });
    const removed = await trx('sales').where({ id: s.id, shop_id: sid }).del();
    if (removed !== 1) throw Object.assign(new Error('Sale changed; refresh and retry'), { status: 409 });
    return true;
  });
  if (!cancelled) return res.status(404).json({ error: 'Sale nahi mila' });
  res.json({ ok: true });
}));

// ---------- REPORTS ----------
r.get('/reports/summary', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const { from, to } = V.range(req.query);
  const buy = await db('phones').where({ shop_id: sid }).whereBetween('buy_date', [from, to]).count('* as c').sum('buy_price as v').first();
  const sale = await db('sales as s').join('phones as p', 'p.id', 's.phone_id').where('s.shop_id', sid)
    .whereBetween('s.sell_date', [from, to]).count('* as c').sum('s.sell_price as v')
    .select(db.raw('SUM(COALESCE(??, ??)) as ??', ['s.buy_price_at_sale', 'p.buy_price', 'cost'])).first();
  const stock = await db('phones').where({ shop_id: sid, status: 'in_stock' }).count('* as c').sum('buy_price as v').first();
  const byPay = await db('sales').where({ shop_id: sid }).whereBetween('sell_date', [from, to])
    .groupBy('payment_mode').select('payment_mode').sum('sell_price as total').count('* as count');
  const topModels = await db('sales as s').join('phones as p', 'p.id', 's.phone_id').where('s.shop_id', sid)
    .whereBetween('s.sell_date', [from, to]).groupBy('p.brand', 'p.model').select('p.brand', 'p.model')
    .count('* as count').orderBy('count', 'desc').limit(5);
  const saleV = +sale.v || 0, cost = +sale.cost || 0;
  res.json({
    from, to,
    purchases: { count: +buy.c, amount: +buy.v || 0 },
    sales: { count: +sale.c, amount: saleV, profit: saleV - cost },
    stock: { count: +stock.c, value: +stock.v || 0 },
    by_payment: byPay.map(x => ({ mode: x.payment_mode, total: +x.total, count: +x.count })),
    top_models: topModels.map(x => ({ ...x, count: +x.count })),
  });
}));

// Roz ka hisaab (chart ke liye)
r.get('/reports/daily', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const { from, to } = V.range(req.query);
  const rows = await db('sales as s').join('phones as p', 'p.id', 's.phone_id').where('s.shop_id', sid)
    .whereBetween('s.sell_date', [from, to]).groupBy('s.sell_date').select('s.sell_date as date')
    .count('* as count').sum('s.sell_price as sales')
    .select(db.raw('SUM(COALESCE(??, ??)) as ??', ['s.buy_price_at_sale', 'p.buy_price', 'cost']))
    .orderBy('s.sell_date');
  res.json(rows.map(x => ({ date: x.date, count: +x.count, sales: +x.sales, profit: +x.sales - +x.cost })));
}));
module.exports = r;
