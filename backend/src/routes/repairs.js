// REPAIR JOBS — customer ke device ka service kaam (stock se alag).
//
// Ye router `routes/shop.js` ke **andar** mount hota hai, isliye:
//   * `requireAuth` pehle hi lag chuka hai (req.user maujood),
//   * Super Admin ka support-access guard bhi pehle chal chuka hai (read-only,
//     reason + time limit + log) — repair routes par bhi wahi niyam lagte hain.
//
// Design rule jo poore module me hai: **customer ka phone kabhi `phones` table
// me nahi jaata** (warna stock value, duplicate-IMEI check aur profit galat ho
// jate). `phone_id` sirf do case me bharta hai —
//   B) shop ne faulty phone khareeda, repair karke bechna hai  → phone pehle se stock me
//   C) customer ka phone shop ne khareed liya                  → "convert to stock"
const r = require('express').Router();
const db = require('../db');
const { today, wrap } = require('../util');
const V = require('../validation');

/// shop_id: shop user → uski shop; superadmin → chalu support session ki shop
/// (guard ne `supportShopId` set kiya hota hai, warna null).
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

const moneyNumber = v => Math.round((Number(v) || 0) * 100) / 100;
const dateOnly = value => (value instanceof Date ? value.toISOString().slice(0, 10) : String(value ?? '').slice(0, 10));

function jobNumber(sid, id) {
  return `RPR-${String(sid).padStart(3, '0')}-${String(id).padStart(6, '0')}`;
}

/// Customer ko dikhne wali list: internal diagnosis, lock note aur parts cost
/// kabhi list me nahi jaate (PDF/receipt wahi rule follow karti hai).
const REPAIR_LIST_COLUMNS = ['id', 'shop_id', 'job_no', 'customer_name', 'customer_phone', 'brand', 'model',
  'imei', 'imei2', 'color', 'status', 'estimate', 'service_charge', 'received_at', 'promised_date',
  'delivered_at', 'warranty_days', 'phone_id', 'created_at', 'updated_at'];

function paymentState(total, paid) {
  const due = Math.max(0, Math.round((total - paid) * 100) / 100);
  return { paid_amount: moneyNumber(paid), balance_due: due,
    payment_status: due <= 0 ? 'paid' : paid > 0 ? 'partial' : 'unpaid' };
}

/// List rows + har job ka paid/balance (ek hi group-by query, N+1 nahi).
async function withRepairTotals(rows, runner = db) {
  if (!rows.length) return rows;
  const sums = await runner('repair_payments').whereIn('repair_id', rows.map(x => x.id))
    .groupBy('repair_id').select('repair_id').sum('amount as paid_amount').count('* as payment_count');
  const byJob = new Map(sums.map(x => [Number(x.repair_id), x]));
  return rows.map(row => {
    const p = byJob.get(Number(row.id));
    const charge = moneyNumber(row.service_charge);
    return {
      ...row,
      estimate: moneyNumber(row.estimate),
      service_charge: charge,
      ...paymentState(charge, moneyNumber(p?.paid_amount)),
      payment_count: Number(p?.payment_count || 0),
    };
  });
}

const OPEN = V.REPAIR_OPEN_STATUSES;

async function repairRow(sid, id, runner = db) {
  return runner('repairs').where({ id, shop_id: sid }).first();
}

async function safeShop(sid) {
  return db('shops').where({ id: sid })
    .select('id', 'name', 'owner_name', 'phone', 'address', 'gst_no', 'logo_data').first();
}

/// IMEI duplicate rule: ek hi IMEI par ek se zyada **khula** job nahi (warna
/// customer ka same phone do baar workshop me dikhega).
async function assertNoOpenJob(sid, imeiValue, excludeId = null, runner = db) {
  if (!imeiValue) return;
  const q = runner('repairs').where({ shop_id: sid, imei: imeiValue }).whereIn('status', OPEN);
  if (excludeId) q.whereNot({ id: excludeId });
  const dup = await q.first('id', 'job_no', 'status');
  if (dup) {
    throw Object.assign(new Error(`Is IMEI ka pehle se khula job hai (${dup.job_no})`),
      { status: 409, code: 'duplicate_imei' });
  }
}

// ---------- LIST ----------
r.get('/repairs', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const status = String(req.query.status ?? 'open');
  if (status !== 'all' && status !== 'open' && !V.REPAIR_STATUSES.includes(status))
    return res.status(400).json({ error: 'status invalid' });
  const search = req.query.search;
  if (search != null && (typeof search !== 'string' || search.length > 100))
    return res.status(400).json({ error: 'search invalid' });
  const dueOnly = String(req.query.due ?? '') === '1';

  const q = db('repairs').where({ shop_id: sid }).select(REPAIR_LIST_COLUMNS);
  if (status === 'open') q.whereIn('status', OPEN);
  else if (status !== 'all') q.where({ status });
  if (search) {
    const s = `%${search}%`;
    q.andWhere(w => w.where('customer_name', 'like', s).orWhere('customer_phone', 'like', s)
      .orWhere('brand', 'like', s).orWhere('model', 'like', s).orWhere('imei', 'like', s)
      .orWhere('job_no', 'like', s));
  }
  const rows = await withRepairTotals(await q.orderBy('id', 'desc'));
  // "Open" list me ready/hold pehle — dukaan ko wahi sabse pehle chahiye.
  const rank = { ready: 0, hold: 1, repairing: 2, received: 3, delivered: 4, cancelled: 5 };
  const sorted = rows.sort((a, b) => {
    const d = (rank[a.status] ?? 9) - (rank[b.status] ?? 9);
    if (d !== 0) return d;
    return String(a.promised_date ?? '9999').localeCompare(String(b.promised_date ?? '9999'));
  });
  res.json(dueOnly ? sorted.filter(x => x.balance_due > 0) : sorted);
}));

// ---------- CREATE ----------
r.post('/repairs', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const b = V.body(req);
  const allowed = ['customer_name', 'customer_phone', 'customer_address', 'brand', 'model', 'imei', 'imei2',
    'serial_number', 'color', 'accessories', 'complaint', 'diagnosis', 'notes', 'device_lock_note',
    'estimate', 'service_charge', 'parts_cost', 'parts_note', 'received_at', 'promised_date',
    'warranty_days', 'phone_id', 'advance'];
  if (Object.keys(b).some(k => !allowed.includes(k))) return res.status(400).json({ error: 'Unsupported repair field' });
  const fields = V.repairData(b);
  const advance = Object.hasOwn(b, 'advance') ? V.moneyOrZero(b.advance, 'advance') : '0.00';
  if (V.cents(advance) > V.cents(fields.estimate) && V.cents(advance) > V.cents(fields.service_charge))
    V.fail('advance estimate/service charge se zyada nahi ho sakta');

  const created = await db.transaction(async trx => {
    await assertNoOpenJob(sid, fields.imei, null, trx);
    // Case B: shop ke apne stock phone ka repair — phone isi shop ka hona chahiye.
    if (fields.phone_id) {
      const phone = await trx('phones').where({ id: fields.phone_id, shop_id: sid }).first('id', 'status');
      if (!phone) V.fail('phone_id isi shop ka nahi hai');
      if (phone.status !== 'in_stock') V.fail('Sirf in-stock phone par repair job ban sakti hai');
    }
    const row = { ...fields, shop_id: sid, status: 'received', created_by: req.user.id,
      updated_at: new Date().toISOString() };
    const [ins] = await trx('repairs').insert(row).returning('id');
    const id = typeof ins === 'object' ? ins.id : ins;
    const jobNo = jobNumber(sid, id);
    await trx('repairs').where({ id }).update({ job_no: jobNo });
    if (V.cents(advance) > 0) {
      await trx('repair_payments').insert({ shop_id: sid, repair_id: id, amount: advance,
        payment_date: fields.received_at, payment_mode: 'cash', kind: 'advance',
        note: 'Advance at booking', created_by: req.user.id });
    }
    return { id, job_no: jobNo };
  });
  res.json(created);
}));

// ---------- ONE JOB ----------
r.get('/repairs/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'repair id');
  const row = await repairRow(sid, id);
  if (!row) return res.status(404).json({ error: 'Repair job nahi mila' });
  const [job] = await withRepairTotals([row]);
  const payments = await db('repair_payments').where({ shop_id: sid, repair_id: id })
    .select('id', 'amount', 'payment_date', 'payment_mode', 'note', 'kind', 'created_at').orderBy('id', 'desc');
  const phone = job.phone_id
    ? await db('phones').where({ id: job.phone_id, shop_id: sid })
      .select('id', 'brand', 'model', 'imei', 'status', 'buy_price', 'repair_cost').first()
    : null;
  res.json({
    ...job,
    payments: payments.map(p => ({ ...p, amount: moneyNumber(p.amount), payment_date: dateOnly(p.payment_date) })),
    phone: phone ? { ...phone, buy_price: moneyNumber(phone.buy_price), repair_cost: moneyNumber(phone.repair_cost) } : null,
    next_statuses: V.REPAIR_FLOW[job.status] ?? [],
  });
}));

// ---------- EDIT ----------
r.put('/repairs/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'repair id');
  const b = V.body(req);
  const allowed = ['customer_name', 'customer_phone', 'customer_address', 'brand', 'model', 'imei', 'imei2',
    'serial_number', 'color', 'accessories', 'complaint', 'diagnosis', 'notes', 'device_lock_note',
    'estimate', 'service_charge', 'parts_cost', 'parts_note', 'promised_date', 'warranty_days', 'phone_id'];
  if (Object.keys(b).some(k => !allowed.includes(k))) return res.status(400).json({ error: 'Unsupported repair field' });
  const job = await repairRow(sid, id);
  if (!job) return res.status(404).json({ error: 'Repair job nahi mila' });
  if (job.status === 'delivered' || job.status === 'cancelled')
    return res.status(409).json({ error: `Delivered/cancelled job edit nahi hoti`, code: 'job_closed' });
  const upd = V.repairData(b, true);
  await db.transaction(async trx => {
    if (Object.hasOwn(upd, 'imei')) await assertNoOpenJob(sid, upd.imei, id, trx);
    if (upd.phone_id) {
      const phone = await trx('phones').where({ id: upd.phone_id, shop_id: sid }).first('id', 'status');
      if (!phone) V.fail('phone_id isi shop ka nahi hai');
      if (phone.status !== 'in_stock') V.fail('Sirf in-stock phone par repair job ban sakti hai');
    }
    // Charge kam ho jaye aur advance usse zyada ho to balance negative ho jata —
    // us case me saaf error.
    const charge = Object.hasOwn(upd, 'service_charge') ? moneyNumber(upd.service_charge) : moneyNumber(job.service_charge);
    const sums = await trx('repair_payments').where({ repair_id: id, shop_id: sid }).sum('amount as paid').first();
    if (V.cents(sums?.paid) > V.cents(charge))
      V.fail('Service charge received amount se kam nahi ho sakta — pehle refund note karein');
    await trx('repairs').where({ id, shop_id: sid })
      .update({ ...upd, updated_at: new Date().toISOString() });
  });
  res.json({ ok: true });
}));

// ---------- STATUS ----------
r.post('/repairs/:id/status', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'repair id');
  const b = V.body(req);
  const allowed = ['status', 'confirm_due', 'note', 'delivered_at', 'warranty_days', 'diagnosis', 'service_charge'];
  if (Object.keys(b).some(k => !allowed.includes(k))) return res.status(400).json({ error: 'Unsupported status field' });
  const next = V.repairStatus(b.status);
  const deliveredAt = b.delivered_at ? V.date(b.delivered_at, 'delivered_at') : today();

  const result = await db.transaction(async trx => {
    const job = await trx('repairs').where({ id, shop_id: sid }).forUpdate().first();
    if (!job) return null;
    const flow = V.REPAIR_FLOW[job.status] ?? [];
    if (!flow.includes(next)) {
      throw Object.assign(new Error(`${job.status} se ${next} par nahi ja sakte`),
        { status: 409, code: 'invalid_transition' });
    }
    const patch = { status: next, updated_at: new Date().toISOString() };
    if (Object.hasOwn(b, 'diagnosis')) patch.diagnosis = V.text(b.diagnosis, 'diagnosis', { max: 2000 });
    if (Object.hasOwn(b, 'service_charge')) {
      patch.service_charge = V.moneyOrZero(b.service_charge, 'service_charge');
      const sums = await trx('repair_payments').where({ repair_id: id, shop_id: sid }).sum('amount as paid').first();
      if (V.cents(sums?.paid) > V.cents(patch.service_charge))
        V.fail('Service charge received amount se kam nahi ho sakta');
    }
    if (Object.hasOwn(b, 'warranty_days')) {
      const n = b.warranty_days == null || b.warranty_days === '' ? null : Number(b.warranty_days);
      if (n != null && (!Number.isInteger(n) || n < 0 || n > 3650)) V.fail('warranty_days must be 0-3650');
      patch.warranty_days = n;
    }

    // Delivery: balance ho to saaf confirmation chahiye (galti se udhaar chhoot na jaye).
    if (next === 'delivered') {
      const charge = moneyNumber(patch.service_charge ?? job.service_charge);
      const sums = await trx('repair_payments').where({ repair_id: id, shop_id: sid }).sum('amount as paid').first();
      const due = moneyNumber(charge - moneyNumber(sums?.paid));
      if (due > 0 && b.confirm_due !== true) {
        throw Object.assign(new Error(`₹${due.toFixed(2)} pending hai — deliver karne ke liye confirm karein (due ledger me rahega)`),
          { status: 409, code: 'balance_due', balance_due: due });
      }
      patch.delivered_at = deliveredAt;
      // Case B: shop ke apne phone par laga kharch uske cost me judta hai (ek hi baar).
      if (job.phone_id && job.status !== 'delivered') {
        const add = moneyNumber(charge) + moneyNumber(job.parts_cost);
        if (add > 0) {
          const phone = await trx('phones').where({ id: job.phone_id, shop_id: sid }).first('id', 'repair_cost');
          if (phone) {
            await trx('phones').where({ id: job.phone_id, shop_id: sid })
              .update({ repair_cost: moneyNumber(moneyNumber(phone.repair_cost) + add) });
          }
        }
      }
    }
    if (next === 'cancelled' && job.status === 'delivered')
      throw Object.assign(new Error('Delivered job cancel nahi hoti'), { status: 409, code: 'job_closed' });
    // Reopen (cancelled → received) par delivery date hatao.
    if (next === 'received') patch.delivered_at = null;

    await trx('repairs').where({ id, shop_id: sid }).update(patch);
    return { ok: true, status: next };
  });
  if (!result) return res.status(404).json({ error: 'Repair job nahi mila' });
  res.json(result);
}));

// ---------- PAYMENTS ----------
r.post('/repairs/:id/payments', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'repair id');
  const b = V.body(req);
  const allowed = ['amount', 'payment_date', 'payment_mode', 'note', 'kind'];
  if (Object.keys(b).some(k => !allowed.includes(k))) return res.status(400).json({ error: 'Unsupported payment field' });
  const payment = V.repairPaymentData(b);

  const result = await db.transaction(async trx => {
    const job = await trx('repairs').where({ id, shop_id: sid }).forUpdate().first();
    if (!job) return null;
    if (job.status === 'cancelled') V.fail('Cancelled job par payment nahi le sakte');
    if (payment.payment_date < dateOnly(job.received_at))
      V.fail('Payment date received date se pehle nahi ho sakti');
    const sums = await trx('repair_payments').where({ repair_id: id, shop_id: sid }).sum('amount as paid').first();
    const paid = moneyNumber(sums?.paid);
    const charge = moneyNumber(job.service_charge);
    if (payment.kind === 'refund') {
      if (V.cents(payment.amount) > V.cents(paid)) V.fail('Refund received amount se zyada nahi ho sakta');
      await trx('repair_payments').insert({ ...payment, amount: `-${payment.amount}`, shop_id: sid,
        repair_id: id, created_by: req.user.id });
      return { ok: true, ...paymentState(charge, paid - moneyNumber(payment.amount)) };
    }
    const due = Math.max(0, moneyNumber(charge - paid));
    if (V.cents(payment.amount) > V.cents(due)) V.fail(`Payment balance ₹${due.toFixed(2)} se zyada nahi ho sakta`);
    await trx('repair_payments').insert({ ...payment, shop_id: sid, repair_id: id, created_by: req.user.id });
    return { ok: true, ...paymentState(charge, paid + moneyNumber(payment.amount)) };
  });
  if (!result) return res.status(404).json({ error: 'Repair job nahi mila' });
  res.json(result);
}));

// ---------- DELETE ----------
r.delete('/repairs/:id', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'repair id');
  const job = await repairRow(sid, id);
  if (!job) return res.status(404).json({ error: 'Repair job nahi mila' });
  if (!['received', 'cancelled'].includes(job.status))
    return res.status(409).json({ error: 'Sirf received/cancelled job delete ho sakti hai — pehle cancel karein',
      code: 'job_open' });
  const paid = await db('repair_payments').where({ repair_id: id, shop_id: sid }).sum('amount as paid').first();
  if (moneyNumber(paid?.paid) !== 0)
    return res.status(409).json({ error: 'Payment li hui job delete nahi hoti — pehle refund note karein',
      code: 'has_payments' });
  await db('repairs').where({ id, shop_id: sid }).del();
  res.json({ ok: true });
}));

// ---------- JOB SHEET (customer-safe) ----------
// Customer ke haath me jaane wala document: diagnosis, parts_cost, lock note aur
// internal notes **kabhi nahi**. Wahi niyam jo sale invoice par hai.
r.get('/repairs/:id/job-sheet', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'repair id');
  const row = await repairRow(sid, id);
  if (!row) return res.status(404).json({ error: 'Repair job nahi mila' });
  const [job] = await withRepairTotals([row]);
  const payments = await db('repair_payments').where({ shop_id: sid, repair_id: id })
    .select('amount', 'payment_date', 'payment_mode', 'kind').orderBy('id', 'asc');
  res.json({
    type: job.status === 'delivered' ? 'delivery' : 'job_sheet',
    number: job.job_no,
    date: dateOnly(job.delivered_at || job.received_at),
    shop: await safeShop(sid),
    customer: { name: job.customer_name, phone: job.customer_phone, address: job.customer_address },
    device: { brand: job.brand, model: job.model, imei: job.imei, imei2: job.imei2,
      color: job.color, accessories: job.accessories },
    complaint: job.complaint,
    received_at: dateOnly(job.received_at),
    promised_date: job.promised_date ? dateOnly(job.promised_date) : null,
    delivered_at: job.delivered_at ? dateOnly(job.delivered_at) : null,
    warranty_days: job.warranty_days,
    estimate: moneyNumber(job.estimate),
    amount: moneyNumber(job.service_charge),
    paid_amount: job.paid_amount,
    balance_due: job.balance_due,
    payment_status: job.payment_status,
    payments: payments.map(p => ({ amount: moneyNumber(p.amount), payment_date: dateOnly(p.payment_date),
      payment_mode: p.payment_mode, kind: p.kind })),
  });
}));

// ---------- CONVERT TO STOCK (customer ka phone shop ne khareed liya) ----------
// Job band ho jata hai aur device `phones` me in_stock chala jata hai. Customer
// details (name/phone/address) purchase row me chali jaati hain, isliye ledger me
// bhi wahi dikhta hai jo ek normal Buy par dikhta hota.
r.post('/repairs/:id/convert-to-stock', wrap(async (req, res) => {
  const sid = needShop(req, res); if (!sid) return;
  const id = V.id(req.params.id, 'repair id');
  const b = V.body(req);
  const allowed = ['buy_price', 'buy_date', 'ram', 'storage', 'condition', 'accessories', 'notes', 'imei'];
  if (Object.keys(b).some(k => !allowed.includes(k))) return res.status(400).json({ error: 'Unsupported field' });
  const job = await repairRow(sid, id);
  if (!job) return res.status(404).json({ error: 'Repair job nahi mila' });
  if (!['received', 'repairing', 'hold', 'ready'].includes(job.status))
    return res.status(409).json({ error: 'Sirf khuli job stock me convert ho sakti hai', code: 'job_closed' });
  if (job.phone_id)
    return res.status(409).json({ error: 'Ye job pehle se kisi stock phone se judi hai', code: 'already_linked' });

  const imeiValue = V.imei(b.imei ?? job.imei, 'imei', true);
  const buyPrice = V.money(b.buy_price, 'buy_price');
  const buyDate = V.date(b.buy_date || today(), 'buy_date');

  const created = await db.transaction(async trx => {
    const dup = await trx('phones').where({ shop_id: sid, status: 'in_stock' })
      .andWhere(w => w.where({ imei: imeiValue }).orWhere({ imei2: imeiValue })).first('id');
    if (dup) V.fail('Ye IMEI pehle se stock me hai');
    const [ins] = await trx('phones').insert({
      shop_id: sid, imei: imeiValue, brand: job.brand, model: job.model,
      ram: V.text(b.ram, 'ram', { max: 255 }),
      storage: V.text(b.storage, 'storage', { max: 255 }),
      color: job.color,
      condition: V.choice(b.condition, 'condition', ['Excellent', 'Good', 'Fair', 'Faulty']) || 'Good',
      accessories: V.text(b.accessories ?? job.accessories, 'accessories', { max: 255 }),
      buy_price: buyPrice, buy_date: buyDate,
      seller_name: job.customer_name, seller_phone: job.customer_phone, seller_address: job.customer_address,
      notes: V.text(b.notes, 'notes', { max: 5000 }) ?? `Purchased from repair job ${job.job_no}`,
      // Repair par laga kharch phone ke cost me — warna profit zyada dikhega.
      repair_cost: moneyNumber(moneyNumber(job.parts_cost) + moneyNumber(job.service_charge)),
      status: 'in_stock', created_by: req.user.id,
    }).returning('id');
    const phoneId = typeof ins === 'object' ? ins.id : ins;
    await trx('repairs').where({ id, shop_id: sid }).update({
      phone_id: phoneId, status: 'cancelled', updated_at: new Date().toISOString(),
      notes: `${job.notes ? job.notes + '\n' : ''}Device purchased by shop → stock #${phoneId} (${job.job_no})`,
    });
    return { id: phoneId };
  });
  res.json({ ok: true, phone_id: created.id });
}));

module.exports = r;
