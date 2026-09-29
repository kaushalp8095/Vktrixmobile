// Shop ka kaam: IMEI lookup, Buy, Stock, Sell, Reports
const r = require('express').Router();
const db = require('../db');
const { requireAuth } = require('../auth');
const { validImei, today, wrap } = require('../util');
r.use(requireAuth);

// shop_id nikalna: shop user -> apni shop; superadmin -> ?shop_id
function shopId(req) {
  if (req.user.role === 'superadmin') return +(req.query.shop_id || req.body.shop_id) || null;
  return req.user.shop_id;
}
function needShop(req, res) {
  const id = shopId(req);
  if (!id) { res.status(400).json({ error: 'shop_id required' }); return null; }
  return id;
}

// ---------- IMEI LOOKUP ----------
r.get('/imei/:imei', wrap(async (req, res) => {
  const imei = req.params.imei.trim();
  const valid = validImei(imei);
  const tac = imei.slice(0, 8);
  const info = await db('tac_models').where({ tac }).first();
  const sid = shopId(req);
  const inStock = sid ? await db('phones').where({ shop_id: sid, imei, status: 'in_stock' }).first() : null;
  const history = sid ? await db('phones').where({ shop_id: sid }).andWhere(q => q.where({ imei }).orWhere({ imei2: imei })).orderBy('id', 'desc') : [];
  res.json({ imei, valid, tac, found: !!info, info: info || null, already_in_stock: !!inStock, history });
}));

// ---------- BUY (stock me add) ----------
r.post('/buy', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const b = req.body;
  if (!validImei(b.imei || '')) return res.status(400).json({ error: 'IMEI galat hai (15 digit, valid hona chahiye)' });
  if (!b.model || !b.buy_price) return res.status(400).json({ error: 'Model aur buy price zaroori hai' });
  if (await db('phones').where({ shop_id: sid, imei: b.imei, status: 'in_stock' }).first())
    return res.status(400).json({ error: 'Ye IMEI pehle se stock me hai' });
  const row = {
    shop_id: sid, imei: b.imei, imei2: b.imei2 || null, brand: b.brand, model: b.model, ram: b.ram, storage: b.storage,
    color: b.color, condition: b.condition, accessories: b.accessories, buy_price: +b.buy_price, buy_date: b.buy_date || today(),
    seller_name: b.seller_name, seller_phone: b.seller_phone, seller_id_type: b.seller_id_type, seller_id_no: b.seller_id_no,
    seller_address: b.seller_address, notes: b.notes, status: 'in_stock', created_by: req.user.id,
  };
  const [ins] = await db('phones').insert(row).returning('id');
  // App khud seekhta hai: agli baar same TAC par info auto-fill
  await db('tac_models').insert({ tac: b.imei.slice(0, 8), brand: b.brand, model: b.model, ram: b.ram, storage: b.storage, color: b.color })
    .onConflict('tac').merge();
  res.json({ id: typeof ins === 'object' ? ins.id : ins });
}));

// ---------- STOCK ----------
r.get('/stock', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const q = db('phones').where({ shop_id: sid, status: req.query.status || 'in_stock' });
  if (req.query.search) {
    const s = `%${req.query.search}%`;
    q.andWhere(w => w.where('imei', 'like', s).orWhere('model', 'like', s).orWhere('brand', 'like', s));
  }
  res.json(await q.orderBy('id', 'desc'));
}));

r.get('/phones/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const p = await db('phones').where({ id: req.params.id, shop_id: sid }).first();
  if (!p) return res.status(404).json({ error: 'Nahi mila' });
  p.sale = await db('sales').where({ phone_id: p.id }).first() || null;
  res.json(p);
}));

r.put('/phones/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const allowed = ['brand', 'model', 'ram', 'storage', 'color', 'condition', 'accessories', 'buy_price', 'buy_date',
    'seller_name', 'seller_phone', 'seller_id_type', 'seller_id_no', 'seller_address', 'notes', 'imei2'];
  const upd = {}; for (const k of allowed) if (k in req.body) upd[k] = req.body[k];
  await db('phones').where({ id: req.params.id, shop_id: sid }).update(upd);
  res.json({ ok: true });
}));

r.delete('/phones/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const n = await db('phones').where({ id: req.params.id, shop_id: sid, status: 'in_stock' }).del();
  res.json({ ok: n > 0 });
}));

// ---------- SELL ----------
r.post('/sell', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const b = req.body;
  if (!b.phone_id || !b.sell_price) return res.status(400).json({ error: 'Phone aur sell price zaroori hai' });
  const id = await db.transaction(async trx => {
    const p = await trx('phones').where({ id: b.phone_id, shop_id: sid, status: 'in_stock' }).first();
    if (!p) throw Object.assign(new Error('Phone stock me nahi hai'), { status: 400 });
    const [ins] = await trx('sales').insert({
      shop_id: sid, phone_id: p.id, sell_price: +b.sell_price, sell_date: b.sell_date || today(),
      customer_name: b.customer_name, customer_phone: b.customer_phone, customer_address: b.customer_address,
      payment_mode: b.payment_mode || 'cash', warranty: b.warranty, notes: b.notes, created_by: req.user.id,
    }).returning('id');
    await trx('phones').where({ id: p.id }).update({ status: 'sold' });
    return typeof ins === 'object' ? ins.id : ins;
  });
  res.json({ id });
}));

r.get('/sales', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const { from = '1900-01-01', to = '2999-12-31' } = req.query;
  res.json(await db('sales as s').join('phones as p', 'p.id', 's.phone_id')
    .where('s.shop_id', sid).whereBetween('s.sell_date', [from, to])
    .select('s.*', 'p.imei', 'p.brand', 'p.model', 'p.ram', 'p.storage', 'p.buy_price')
    .orderBy('s.id', 'desc'));
}));

// Sale cancel -> phone wapas stock me
r.delete('/sales/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  await db.transaction(async trx => {
    const s = await trx('sales').where({ id: req.params.id, shop_id: sid }).first();
    if (!s) return;
    await trx('phones').where({ id: s.phone_id }).update({ status: 'in_stock' });
    await trx('sales').where({ id: s.id }).del();
  });
  res.json({ ok: true });
}));

// ---------- REPORTS ----------
r.get('/reports/summary', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const from = req.query.from || today(), to = req.query.to || today();
  const buy = await db('phones').where({ shop_id: sid }).whereBetween('buy_date', [from, to]).count('* as c').sum('buy_price as v').first();
  const sale = await db('sales as s').join('phones as p', 'p.id', 's.phone_id').where('s.shop_id', sid)
    .whereBetween('s.sell_date', [from, to]).count('* as c').sum('s.sell_price as v').sum('p.buy_price as cost').first();
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
  const from = req.query.from || today(), to = req.query.to || today();
  const rows = await db('sales as s').join('phones as p', 'p.id', 's.phone_id').where('s.shop_id', sid)
    .whereBetween('s.sell_date', [from, to]).groupBy('s.sell_date').select('s.sell_date as date')
    .count('* as count').sum('s.sell_price as sales').sum('p.buy_price as cost').orderBy('s.sell_date');
  res.json(rows.map(x => ({ date: x.date, count: +x.count, sales: +x.sales, profit: +x.sales - +x.cost })));
}));
module.exports = r;
