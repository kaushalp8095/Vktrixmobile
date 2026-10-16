// Shop ka kaam: IMEI lookup, Buy, Stock, Sell, Reports
const r = require('express').Router();
const db = require('../db');
const { requireAuth } = require('../auth');
const { validImei, today, wrap } = require('../util');
const V = require('../validation');
const suggestions = require('../suggestions');
const tacApi = require('../tacApi');
const support = require('../support');
r.use(requireAuth);

// ---- SUPER ADMIN KA SHOP DATA PAR ACCESS (backend me, sirf screen par nahi) ----
// Super Admin ke paas is router ke shop data (IMEI, stock, sales, profit, ledger,
// customer/ID info) ka default access **nahi** hai. Wo sirf tab milta hai jab:
//   1. usne us shop ke liye reason ke saath temporary support session li ho,
//   2. session abhi khatam na hua ho,
//   3. request **read-only** ho (GET) — support access se shop ka data badla nahi ja sakta.
// Har read log me dikhti hai (shop owner apni app me dekh sakta hai).
r.use(wrap(async (req, res, next) => {
  if (req.user.role !== 'superadmin') return next();
  const raw = req.query?.shop_id ?? req.body?.shop_id;
  if (raw == null || raw === '') return next();   // catalog-only routes (e.g. /imei catalog lookup)
  let sid;
  try { sid = V.id(raw, 'shop_id'); } catch {
    return res.status(400).json({ error: 'shop_id must be a positive integer', code: 'invalid_shop_id' });
  }
  const grant = await support.activeGrant(sid, req.user.id);
  if (!grant) {
    return res.status(403).json({
      error: 'Shop data dekhne ke liye temporary support access zaroori hai (reason aur time limit ke saath).',
      code: 'support_access_required',
    });
  }
  if (req.method !== 'GET') {
    return res.status(403).json({
      error: 'Support access read-only hai — shop ka data change nahi ho sakta. Ye kaam shop owner khud kare.',
      code: 'support_access_read_only',
    });
  }
  req.supportGrant = grant;
  req.supportShopId = sid;
  await support.markRead(grant);
  next();
}));

// Columns returned by list endpoints. Both customer ID photos are deliberately
// left out: base64 images would bloat every stock/reports response.
// The full row (photo included) is available from GET /phones/:id.
const PHONE_LIST_COLUMNS = ['id', 'shop_id', 'imei', 'imei2', 'serial_number', 'brand', 'model', 'ram', 'storage',
  'color', 'condition', 'accessories', 'buy_price', 'buy_date', 'seller_name', 'seller_phone', 'seller_id_type',
  'seller_id_no', 'seller_address', 'notes', 'status', 'created_by', 'created_at'];

// shop_id nikalna: shop user -> apni shop; superadmin -> apni chalu support session
// ki shop (upar wala guard set karta hai, warna null).
function shopId(req) {
  if (req.user.role === 'superadmin') return req.supportShopId ?? null;
  return req.user.shop_id;
}
function needShop(req, res) {
  const id = shopId(req);
  if (!id) {
    if (req.user.role === 'superadmin')
      return void res.status(403).json({ error: 'Shop data dekhne ke liye temporary support access zaroori hai.',
        code: 'support_access_required' });
    res.status(400).json({ error: 'shop_id required' });
    return null;
  }
  return id;
}
function isUniqueViolation(err) {
  return err?.code === '23505' || err?.code === 'SQLITE_CONSTRAINT_UNIQUE' ||
    err?.code === 'SQLITE_CONSTRAINT_PRIMARYKEY' || /unique constraint failed/i.test(err?.message || '');
}
function dateOnly(value) {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value ?? '').slice(0, 10);
}
function moneyNumber(value) { return Math.round((Number(value) || 0) * 100) / 100; }
function paymentStatus(total, paid) {
  const due = Math.max(0, Math.round((total - paid) * 100) / 100);
  return { paid_amount: moneyNumber(paid), balance_due: due,
    payment_status: due <= 0 ? 'paid' : paid > 0 ? 'partial' : 'unpaid' };
}
async function withPaymentTotals(rows, runner = db) {
  if (!rows.length) return rows;
  const sums = await runner('sale_payments').whereIn('sale_id', rows.map(x => x.id))
    .groupBy('sale_id').select('sale_id').sum('amount as paid_amount').count('* as payment_count');
  const bySale = new Map(sums.map(x => [Number(x.sale_id), x]));
  return rows.map(row => {
    const p = bySale.get(Number(row.id));
    return { ...row, ...paymentStatus(moneyNumber(row.sell_price), moneyNumber(p?.paid_amount)),
      payment_count: Number(p?.payment_count || 0) };
  });
}
async function safeShop(sid, runner = db) {
  return runner('shops').where({ id: sid })
    .select('id', 'name', 'owner_name', 'phone', 'address', 'gst_no', 'logo_data').first();
}
function receiptNumber(kind, sid, id) {
  return `${kind === 'sale' ? 'INV' : 'PUR'}-${String(sid).padStart(3, '0')}-${String(id).padStart(6, '0')}`;
}
async function safeSale(sid, saleId, runner = db) {
  return runner('sales as s').join('phones as p', 'p.id', 's.phone_id')
    .where({ 's.id': saleId, 's.shop_id': sid })
    .select('s.id', 's.shop_id', 's.phone_id', 's.sell_price', 's.sell_date', 's.customer_name',
      's.customer_phone', 's.customer_address', 's.payment_mode', 's.warranty', 's.notes', 's.created_at',
      'p.imei', 'p.imei2', 'p.serial_number', 'p.brand', 'p.model', 'p.ram', 'p.storage', 'p.color',
      'p.condition', 'p.accessories').first();
}

// ---------- SUPPORT ACCESS LOG (shop owner ke liye) ----------
// Shop owner dekhta hai ki Vktrix support ne uske data ko kab, kyun aur kitna dekha.
// Yahan sirf apni shop ka log milta hai (shop_id query ignore hoti hai).
r.get('/support-access', wrap(async (req, res) => {
  const sid = shopId(req);
  if (!sid) return res.status(400).json({ error: 'shop_id required' });
  const items = await support.list({ shopId: sid, limit: req.query.limit });
  const running = await support.activeGrant(sid);
  res.json({
    items,
    active: running ? support.shape(running) : null,
  });
}));

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
    'customer_id_photo', 'customer_id_photo_back'];
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
    'serial_number', 'customer_id_photo', 'customer_id_photo_back'];
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
  const b = V.body(req);
  const allowed = ['phone_id', 'sell_price', 'sell_date', 'customer_name', 'customer_phone', 'customer_address',
    'payment_mode', 'amount_received', 'warranty', 'notes'];
  if (Object.keys(b).some(k => !allowed.includes(k))) return res.status(400).json({ error: 'Unsupported sale field' });
  const sale = V.saleData(b);
  try {
    const id = await db.transaction(async trx => {
      // PostgreSQL row lock serializes competing sales. Conditional update and
      // unique sales.phone_id index are defense in depth for every supported DB.
      const p = await trx('phones').where({ id: sale.phone_id, shop_id: sid, status: 'in_stock' }).forUpdate().first();
      if (!p) throw Object.assign(new Error('Phone stock me nahi hai ya pehle hi sell ho chuka hai'), { status: 409 });
      const boughtOn = dateOnly(p.buy_date);
      if (sale.sell_date < boughtOn) V.fail('Sell date buy date se pehle nahi ho sakti');
      const changed = await trx('phones').where({ id: p.id, shop_id: sid, status: 'in_stock' }).update({ status: 'sold' });
      if (changed !== 1) throw Object.assign(new Error('Phone already sold; stock refresh karein'), { status: 409 });
      const { amount_received: received, ...saleRow } = sale;
      const [ins] = await trx('sales').insert({
        ...saleRow, shop_id: sid, buy_price_at_sale: p.buy_price, created_by: req.user.id,
      }).returning('id');
      const saleId = typeof ins === 'object' ? ins.id : ins;
      if (V.cents(received) > 0) {
        const collectionMode = ['cash', 'upi', 'card', 'bank'].includes(sale.payment_mode) ? sale.payment_mode : 'other';
        await trx('sale_payments').insert({ shop_id: sid, sale_id: saleId, amount: received,
          payment_date: sale.sell_date, payment_mode: collectionMode, note: 'Payment received at sale', created_by: req.user.id });
      }
      return saleId;
    });
    res.json({ id, ...paymentStatus(moneyNumber(sale.sell_price), moneyNumber(sale.amount_received)) });
  } catch (err) {
    if (isUniqueViolation(err) || ['SQLITE_BUSY', 'SQLITE_LOCKED'].includes(err?.code))
      return res.status(409).json({ error: 'Phone already has a sale or is being sold; stock refresh karein' });
    throw err;
  }
}));

r.get('/sales', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const { from, to } = V.range(req.query, ['1900-01-01', '2999-12-31']);
  const rows = await db('sales as s').join('phones as p', 'p.id', 's.phone_id')
    .where('s.shop_id', sid).whereBetween('s.sell_date', [from, to])
    .select('s.*', 'p.imei', 'p.imei2', 'p.serial_number', 'p.brand', 'p.model', 'p.ram', 'p.storage', 'p.color')
    .select(db.raw('COALESCE(??, ??) as ??', ['s.buy_price_at_sale', 'p.buy_price', 'buy_price']))
    .orderBy('s.id', 'desc');
  res.json(await withPaymentTotals(rows));
}));

// ---------- CUSTOMER RECEIPTS (safe, no cost/profit/ID photos/notes) ----------
r.get('/receipts/purchase/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'phone id');
  const p = await db('phones').where({ id, shop_id: sid }).select('id', 'shop_id', 'imei', 'imei2', 'serial_number',
    'brand', 'model', 'ram', 'storage', 'color', 'condition', 'accessories', 'buy_price', 'buy_date',
    'seller_name', 'seller_phone', 'seller_address').first();
  if (!p) return res.status(404).json({ error: 'Purchase nahi mila' });
  res.json({
    type: 'purchase', number: receiptNumber('purchase', sid, p.id), date: dateOnly(p.buy_date),
    shop: await safeShop(sid),
    customer: { name: p.seller_name, phone: p.seller_phone, address: p.seller_address },
    phone: { imei: p.imei, imei2: p.imei2, serial_number: p.serial_number, brand: p.brand, model: p.model,
      ram: p.ram, storage: p.storage, color: p.color, condition: p.condition, accessories: p.accessories },
    amount: moneyNumber(p.buy_price),
  });
}));

r.get('/receipts/sale/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'sale id');
  const row = await safeSale(sid, id);
  if (!row) return res.status(404).json({ error: 'Sale nahi mila' });
  const [sale] = await withPaymentTotals([row]);
  res.json({
    type: 'sale', number: receiptNumber('sale', sid, sale.id), date: dateOnly(sale.sell_date),
    shop: await safeShop(sid),
    customer: { name: sale.customer_name, phone: sale.customer_phone, address: sale.customer_address },
    phone: { imei: sale.imei, imei2: sale.imei2, serial_number: sale.serial_number, brand: sale.brand,
      model: sale.model, ram: sale.ram, storage: sale.storage, color: sale.color,
      condition: sale.condition, accessories: sale.accessories },
    amount: moneyNumber(sale.sell_price), warranty: sale.warranty, payment_mode: sale.payment_mode,
    paid_amount: sale.paid_amount, balance_due: sale.balance_due, payment_status: sale.payment_status,
  });
}));

// ---------- UDHAAR / PARTIAL-PAYMENT LEDGER ----------
r.get('/ledger', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const status = req.query.status || 'pending';
  if (!['pending', 'paid', 'all'].includes(status)) return res.status(400).json({ error: 'status invalid' });
  if (req.query.search != null && (typeof req.query.search !== 'string' || req.query.search.length > 100))
    return res.status(400).json({ error: 'search invalid' });
  const q = db('sales as s').join('phones as p', 'p.id', 's.phone_id').where('s.shop_id', sid)
    .select('s.id', 's.sell_price', 's.sell_date', 's.customer_name', 's.customer_phone', 's.payment_mode',
      's.warranty', 'p.imei', 'p.brand', 'p.model', 'p.ram', 'p.storage').orderBy('s.id', 'desc');
  if (req.query.search) {
    const term = `%${req.query.search}%`;
    q.andWhere(w => w.where('s.customer_name', 'like', term).orWhere('s.customer_phone', 'like', term)
      .orWhere('p.imei', 'like', term).orWhere('p.brand', 'like', term).orWhere('p.model', 'like', term));
  }
  const all = await withPaymentTotals(await q);
  const pending = all.filter(x => x.balance_due > 0);
  const filtered = status === 'all' ? all : status === 'paid' ? all.filter(x => x.balance_due <= 0) : pending;
  res.json({
    summary: {
      outstanding: moneyNumber(pending.reduce((n, x) => n + x.balance_due, 0)),
      pending_count: pending.length,
      received: moneyNumber(all.reduce((n, x) => n + x.paid_amount, 0)),
      sales_total: moneyNumber(all.reduce((n, x) => n + moneyNumber(x.sell_price), 0)),
    },
    items: filtered,
  });
}));

r.get('/sales/:id/payments', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'sale id');
  const row = await safeSale(sid, id);
  if (!row) return res.status(404).json({ error: 'Sale nahi mila' });
  const [sale] = await withPaymentTotals([row]);
  const payments = await db('sale_payments').where({ sale_id: id, shop_id: sid })
    .select('id', 'amount', 'payment_date', 'payment_mode', 'note', 'created_at').orderBy('id', 'desc');
  res.json({ sale: { ...sale, number: receiptNumber('sale', sid, id), sell_date: dateOnly(sale.sell_date) },
    shop: await safeShop(sid), payments: payments.map(p => ({ ...p, amount: moneyNumber(p.amount), payment_date: dateOnly(p.payment_date) })) });
}));

r.post('/sales/:id/payments', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const saleId = V.id(req.params.id, 'sale id');
  const b = V.body(req);
  const allowed = ['amount', 'payment_date', 'payment_mode', 'note'];
  if (Object.keys(b).some(k => !allowed.includes(k))) return res.status(400).json({ error: 'Unsupported payment field' });
  const payment = V.paymentData(b);
  const result = await db.transaction(async trx => {
    const sale = await trx('sales').where({ id: saleId, shop_id: sid }).forUpdate().first();
    if (!sale) return null;
    if (payment.payment_date < dateOnly(sale.sell_date)) V.fail('Payment date sell date se pehle nahi ho sakti');
    const sum = await trx('sale_payments').where({ sale_id: saleId, shop_id: sid }).sum('amount as paid').first();
    const paid = moneyNumber(sum?.paid);
    const due = Math.max(0, moneyNumber(sale.sell_price) - paid);
    if (V.cents(payment.amount) > V.cents(due)) V.fail(`Payment balance ${due.toFixed(2)} se zyada nahi ho sakta`);
    const [ins] = await trx('sale_payments').insert({ ...payment, shop_id: sid, sale_id: saleId, created_by: req.user.id }).returning('id');
    const paymentId = typeof ins === 'object' ? ins.id : ins;
    return { id: paymentId, ...paymentStatus(moneyNumber(sale.sell_price), paid + moneyNumber(payment.amount)) };
  });
  if (!result) return res.status(404).json({ error: 'Sale nahi mila' });
  res.json(result);
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
    // Explicit delete also works on legacy SQLite databases where foreign-key
    // cascades may not have been enabled when the connection was created.
    await trx('sale_payments').where({ sale_id: s.id, shop_id: sid }).del();
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
  const periodSales = await db('sales').where({ shop_id: sid }).whereBetween('sell_date', [from, to])
    .select('id', 'sell_price');
  const paidPeriodSales = await withPaymentTotals(periodSales);
  const saleV = +sale.v || 0, cost = +sale.cost || 0;
  res.json({
    from, to,
    purchases: { count: +buy.c, amount: +buy.v || 0 },
    sales: { count: +sale.c, amount: saleV, profit: saleV - cost },
    stock: { count: +stock.c, value: +stock.v || 0 },
    receivables: {
      outstanding: moneyNumber(paidPeriodSales.reduce((n, x) => n + x.balance_due, 0)),
      received: moneyNumber(paidPeriodSales.reduce((n, x) => n + x.paid_amount, 0)),
      pending_count: paidPeriodSales.filter(x => x.balance_due > 0).length,
    },
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
