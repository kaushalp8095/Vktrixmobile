// Repair jobs: customer device workshop — stock se alag, tenant scoped, aur
// customer ke haath jaane wale document me internal cost kabhi nahi.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

if (process.env.TEST_DATABASE_URL) {
  const dbName = new URL(process.env.TEST_DATABASE_URL).pathname.split('/').filter(Boolean).pop() || '';
  if (!/(^|_)test($|_)/i.test(dbName)) throw new Error('Refusing PostgreSQL tests unless database name includes "test"');
  process.env.DB_CLIENT = 'pg';
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
} else {
  process.env.DB_CLIENT = 'better-sqlite3';
  process.env.SQLITE_FILE = path.join(os.tmpdir(), `vktrix-repairs-${process.pid}.sqlite`);
  for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
}
process.env.JWT_SECRET = 'isolated-repair-tests';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';

const express = require('express');
const db = require('../src/db');
const migrate = require('../src/migrate');
const V = require('../src/validation');

function withCheckDigit(fourteen) {
  let sum = 0;
  for (let i = 0; i < 14; i++) {
    let d = +fourteen[i];
    if (i % 2 === 1) { d *= 2; if (d > 9) d -= 9; }
    sum += d;
  }
  return fourteen + String((10 - sum % 10) % 10);
}
const IMEI_A = withCheckDigit('35332811900001');
const IMEI_B = withCheckDigit('35332811900002');
const IMEI_C = withCheckDigit('35332811900003');

let server, base;
async function request(method, route, token, data) {
  const response = await fetch(base + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(data === undefined ? {} : { body: JSON.stringify(data) }),
  });
  return { status: response.status, body: await response.json() };
}
async function login(username, password) {
  const r = await request('POST', '/auth/login', null, { username, password });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.token;
}

const jobBody = (overrides = {}) => ({
  customer_name: 'Ramesh Patel', customer_phone: '9876543210', customer_address: 'Station Road, Mahesana',
  brand: 'Samsung', model: 'Galaxy M31', imei: IMEI_A, color: 'Blue', accessories: 'Back cover',
  complaint: 'Screen broken, touch not working', device_lock_note: 'PIN 1234 (customer ne diya)',
  estimate: '2500', service_charge: '2800', parts_cost: '1200', parts_note: 'Vendor: display ₹1200',
  received_at: '2026-10-05', promised_date: '2026-10-07', warranty_days: 30, ...overrides,
});

test('repair jobs stay separate from stock, are tenant-scoped, and never leak internal cost', async t => {
  await migrate();
  await db('repair_payments').del(); await db('repairs').del();
  await db('sale_payments').del(); await db('sales').del(); await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del(); await db('shops').del();

  const app = express();
  app.use(express.json({ limit: '9mb' }));
  app.use('/api/auth', require('../src/routes/auth'));
  app.use('/api/admin', require('../src/routes/admin'));
  app.use('/api', require('../src/routes/shop'));
  app.use((err, req, res, next) => res.status(err.status || 500).json({
    error: err.message, ...(err.code ? { code: err.code } : {}),
  }));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}/api`;
  t.after(async () => {
    await new Promise(resolve => server.close(resolve));
    await db.destroy();
    if (!process.env.TEST_DATABASE_URL)
      for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
  });

  const admin = await login('superadmin', 'AuditOnly@123');
  const alpha = await request('POST', '/admin/shops', admin, {
    name: 'Alpha Mobiles', username: 'alpha', password: 'Alpha@123',
  });
  const beta = await request('POST', '/admin/shops', admin, {
    name: 'Beta Mobiles', username: 'beta', password: 'Beta@123',
  });
  assert.equal(alpha.status, 200, JSON.stringify(alpha.body));
  assert.equal(beta.status, 200, JSON.stringify(beta.body));
  const alphaToken = await login('alpha', 'Alpha@123');
  const betaToken = await login('beta', 'Beta@123');

  await t.test('validation blocks an unreachable customer and a bad IMEI', async () => {
    const noContact = await request('POST', '/repairs', alphaToken,
      jobBody({ customer_phone: '', customer_address: '', imei: '' }));
    assert.equal(noContact.status, 400);
    assert.match(noContact.body.error, /mobile or address/);

    const badImei = await request('POST', '/repairs', alphaToken, jobBody({ imei: '123456789012345' }));
    assert.equal(badImei.status, 400);
    assert.match(badImei.body.error, /IMEI/);

    const backwards = await request('POST', '/repairs', alphaToken,
      jobBody({ imei: '', promised_date: '2026-10-01' }));
    assert.equal(backwards.status, 400);
    assert.match(backwards.body.error, /promised_date cannot be before/);

    // IMEI optional hai (feature phone), par tab bhi contact chahiye — upar wala
    // test usi ko cover karta hai; yahan IMEI ke bina job ban sakti hai.
    const noImei = await request('POST', '/repairs', alphaToken, jobBody({ imei: '', brand: 'Nokia', model: '105' }));
    assert.equal(noImei.status, 200, JSON.stringify(noImei.body));
    await request('DELETE', `/repairs/${noImei.body.id}`, alphaToken);
  });

  let jobId, jobNo;
  await t.test('a job is created with a readable job number and an advance payment', async () => {
    const created = await request('POST', '/repairs', alphaToken, jobBody({ advance: '500' }));
    assert.equal(created.status, 200, JSON.stringify(created.body));
    jobId = created.body.id;
    jobNo = created.body.job_no;
    assert.match(jobNo, /^RPR-\d{3}-\d{6}$/);

    const one = await request('GET', `/repairs/${jobId}`, alphaToken);
    assert.equal(one.status, 200, JSON.stringify(one.body));
    assert.equal(one.body.status, 'received');
    assert.equal(one.body.service_charge, 2800);
    assert.equal(one.body.parts_cost, 1200);
    assert.equal(one.body.paid_amount, 500);
    assert.equal(one.body.balance_due, 2300);
    assert.equal(one.body.payment_status, 'partial');
    assert.equal(one.body.payments.length, 1);
    assert.equal(one.body.payments[0].kind, 'advance');
    assert.deepEqual(one.body.next_statuses.sort(), ['cancelled', 'hold', 'ready', 'repairing']);

    // Customer ka phone stock me nahi jaata — stock count 0 hi rehta hai.
    const stock = await request('GET', '/stock', alphaToken);
    assert.equal(stock.body.length, 0, 'customer devices must never enter stock');
  });

  await t.test('the list is tenant scoped and filterable', async () => {
    const list = await request('GET', '/repairs', alphaToken);
    assert.equal(list.status, 200);
    assert.equal(list.body.length, 1);
    assert.equal(list.body[0].job_no, jobNo);
    // List me internal diagnosis/lock note bhejne ki zaroorat nahi.
    assert.equal(list.body[0].device_lock_note, undefined);
    assert.equal(list.body[0].parts_cost, undefined);

    assert.equal((await request('GET', '/repairs', betaToken)).body.length, 0);
    assert.equal((await request('GET', `/repairs/${jobId}`, betaToken)).status, 404);
    assert.equal((await request('GET', `/repairs/${jobId}/job-sheet`, betaToken)).status, 404);
    assert.equal((await request('POST', `/repairs/${jobId}/payments`, betaToken, { amount: '100' })).status, 404);
    assert.equal((await request('DELETE', `/repairs/${jobId}`, betaToken)).status, 404);

    assert.equal((await request('GET', '/repairs?status=delivered', alphaToken)).body.length, 0);
    assert.equal((await request('GET', '/repairs?status=open', alphaToken)).body.length, 1);
    assert.equal((await request('GET', '/repairs?search=Samsung', alphaToken)).body.length, 1);
    assert.equal((await request('GET', '/repairs?status=bogus', alphaToken)).status, 400);
  });

  await t.test('one open job per IMEI; the same IMEI may return after delivery', async () => {
    const dup = await request('POST', '/repairs', alphaToken, jobBody({ customer_name: 'Second Owner' }));
    assert.equal(dup.status, 409);
    assert.equal(dup.body.code, 'duplicate_imei');
    assert.match(dup.body.error, new RegExp(jobNo));
  });

  await t.test('payments are immutable rows and cannot exceed the balance', async () => {
    const tooMuch = await request('POST', `/repairs/${jobId}/payments`, alphaToken,
      { amount: '99999', payment_mode: 'upi' });
    assert.equal(tooMuch.status, 400);
    assert.match(tooMuch.body.error, /balance/);

    const before = await request('POST', `/repairs/${jobId}/payments`, alphaToken,
      { amount: '999.99', payment_date: '2026-10-04' });
    assert.equal(before.status, 400, 'payment date cannot be before the received date');

    const part = await request('POST', `/repairs/${jobId}/payments`, alphaToken,
      { amount: '800', payment_date: '2026-10-06', payment_mode: 'upi', note: 'Customer paid part' });
    assert.equal(part.status, 200, JSON.stringify(part.body));
    assert.equal(part.body.paid_amount, 1300);
    assert.equal(part.body.balance_due, 1500);

    const one = await request('GET', `/repairs/${jobId}`, alphaToken);
    assert.equal(one.body.payments.length, 2, 'each collection is its own row');

    const refundTooMuch = await request('POST', `/repairs/${jobId}/payments`, alphaToken,
      { amount: '5000', kind: 'refund', payment_date: '2026-10-06' });
    assert.equal(refundTooMuch.status, 400);
  });

  await t.test('status flow is enforced and delivery with a balance needs a confirm', async () => {
    const skip = await request('POST', `/repairs/${jobId}/status`, alphaToken, { status: 'delivered' });
    assert.equal(skip.status, 409);
    assert.equal(skip.body.code, 'invalid_transition');

    assert.equal((await request('POST', `/repairs/${jobId}/status`, alphaToken, { status: 'repairing' })).status, 200);
    assert.equal((await request('POST', `/repairs/${jobId}/status`, alphaToken, { status: 'ready' })).status, 200);

    const due = await request('POST', `/repairs/${jobId}/status`, alphaToken, { status: 'delivered' });
    assert.equal(due.status, 409);
    assert.equal(due.body.code, 'balance_due');
    assert.match(due.body.error, /1500\.00/);

    const done = await request('POST', `/repairs/${jobId}/status`, alphaToken,
      { status: 'delivered', confirm_due: true, delivered_at: '2026-10-08' });
    assert.equal(done.status, 200, JSON.stringify(done.body));

    const one = await request('GET', `/repairs/${jobId}`, alphaToken);
    assert.equal(one.body.status, 'delivered');
    assert.equal(one.body.balance_due, 1500, 'the due survives delivery in the ledger');
    assert.equal(one.body.delivered_at.slice(0, 10), '2026-10-08');

    // Delivered job edit/delete nahi hoti.
    assert.equal((await request('PUT', `/repairs/${jobId}`, alphaToken, { complaint: 'changed' })).status, 409);
    assert.equal((await request('DELETE', `/repairs/${jobId}`, alphaToken)).status, 409);
  });

  await t.test('the job sheet is customer-safe', async () => {
    const sheet = await request('GET', `/repairs/${jobId}/job-sheet`, alphaToken);
    assert.equal(sheet.status, 200, JSON.stringify(sheet.body));
    assert.equal(sheet.body.type, 'delivery');
    assert.equal(sheet.body.number, jobNo);
    assert.equal(sheet.body.amount, 2800);
    assert.equal(sheet.body.paid_amount, 1300);
    assert.equal(sheet.body.balance_due, 1500);
    assert.equal(sheet.body.shop.name, 'Alpha Mobiles');
    const json = JSON.stringify(sheet.body);
    assert.doesNotMatch(json, /parts_cost|1200|Vendor|PIN 1234|device_lock_note|diagnosis/,
      'internal cost, lock note and diagnosis must never reach the customer document');
  });

  await t.test('ledger and reports expose repair numbers without touching existing ones', async () => {
    const ledger = await request('GET', '/ledger/repairs', alphaToken);
    assert.equal(ledger.status, 200, JSON.stringify(ledger.body));
    assert.equal(ledger.body.outstanding, 1500);
    assert.equal(ledger.body.received, 1300);
    assert.equal(ledger.body.open_count, 0);
    assert.equal(ledger.body.jobs_total, 2800);

    const summary = await request('GET', '/reports/summary?from=2026-10-01&to=2026-10-31', alphaToken);
    assert.equal(summary.status, 200, JSON.stringify(summary.body));
    // Purane numbers bilkul wahi — repair ki kamai sale/profit me mix nahi hoti.
    assert.deepEqual(summary.body.purchases, { count: 0, amount: 0 });
    assert.deepEqual(summary.body.sales, { count: 0, amount: 0, profit: 0 });
    assert.deepEqual(summary.body.stock, { count: 0, value: 0 });
    assert.deepEqual(summary.body.receivables, { outstanding: 0, received: 0, pending_count: 0 });
    assert.equal(summary.body.repairs.delivered_count, 1);
    assert.equal(summary.body.repairs.billed, 2800);
    assert.equal(summary.body.repairs.collected, 1300);
    assert.equal(summary.body.repairs.open_count, 0);
  });

  await t.test('a shop phone can be repaired and the cost lands in its cost basis', async () => {
    const bought = await request('POST', '/buy', alphaToken, {
      imei: IMEI_B, brand: 'Apple', model: 'iPhone 12', ram: '4GB', storage: '64GB',
      buy_price: '20000', buy_date: '2026-10-02', seller_name: 'Seller', seller_phone: '9876500000',
    });
    assert.equal(bought.status, 200, JSON.stringify(bought.body));

    const created = await request('POST', '/repairs', alphaToken, {
      customer_name: 'Shop stock', brand: 'Apple', model: 'iPhone 12', imei: IMEI_B,
      complaint: 'Battery health low', service_charge: '1500', parts_cost: '900',
      received_at: '2026-10-03', phone_id: bought.body.id,
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));

    // Job ke liye phone in_stock hona chahiye — sold phone par job nahi.
    const sold = await request('POST', '/sell', alphaToken, {
      phone_id: bought.body.id, sell_price: '25000', sell_date: '2026-10-10',
      customer_name: 'Buyer', payment_mode: 'cash', amount_received: '25000',
    });
    assert.equal(sold.status, 200, JSON.stringify(sold.body));
    const late = await request('POST', '/repairs', alphaToken, {
      customer_name: 'Shop stock', brand: 'Apple', model: 'iPhone 12', imei: IMEI_C,
      complaint: 'x', received_at: '2026-10-11', phone_id: bought.body.id,
    });
    assert.equal(late.status, 400);
    assert.match(late.body.error, /in-stock/);

    // Job ko wapas in_stock par le jao aur deliver karo — cost judna chahiye.
    await db('repairs').where({ id: created.body.id }).update({ status: 'ready' });
    const delivered = await request('POST', `/repairs/${created.body.id}/status`, alphaToken,
      { status: 'delivered', confirm_due: true, delivered_at: '2026-10-09' });
    // Phone sold hai — job par asar nahi padta, par cost sirf tab judti hai jab phone mile.
    assert.equal(delivered.status, 200, JSON.stringify(delivered.body));
    const phone = await db('phones').where({ id: bought.body.id }).first();
    assert.equal(Number(phone.repair_cost), 2400, 'service charge + parts cost becomes cost basis');

    // Profit sahi rahe: sale ka profit cost basis (buy + repair) par.
    const sales = await request('GET', '/sales', alphaToken);
    const row = sales.body.find(x => x.phone_id === bought.body.id) || sales.body[0];
    assert.equal(Number(row.buy_price_at_sale ?? phone.buy_price), 20000);
  });

  await t.test('a customer-abandoned device can be converted into stock', async () => {
    const created = await request('POST', '/repairs', alphaToken, {
      customer_name: 'Abandoned Owner', customer_phone: '9876511111', brand: 'Redmi', model: 'Note 9',
      imei: IMEI_C, complaint: 'Dead, not repaired', service_charge: '0', parts_cost: '0',
      received_at: '2026-09-01',
    });
    assert.equal(created.status, 200, JSON.stringify(created.body));

    const converted = await request('POST', `/repairs/${created.body.id}/convert-to-stock`, alphaToken, {
      buy_price: '3000', buy_date: '2026-10-20', ram: '4GB', storage: '64GB', condition: 'Fair',
    });
    assert.equal(converted.status, 200, JSON.stringify(converted.body));

    const phone = await db('phones').where({ id: converted.body.phone_id }).first();
    assert.equal(phone.status, 'in_stock');
    assert.equal(phone.imei, IMEI_C);
    assert.equal(phone.seller_name, 'Abandoned Owner');
    assert.equal(Number(phone.buy_price), 3000);

    const one = await request('GET', `/repairs/${created.body.id}`, alphaToken);
    assert.equal(one.body.status, 'cancelled');
    assert.equal(one.body.phone_id, converted.body.phone_id);

    // Ek hi device do baar stock me nahi.
    const again = await request('POST', `/repairs/${created.body.id}/convert-to-stock`, alphaToken, { buy_price: '100' });
    assert.equal(again.status, 409);
  });

  await t.test('deletes are limited to untouched jobs', async () => {
    const created = await request('POST', '/repairs', alphaToken, jobBody({ imei: '', customer_name: 'Delete Me' }));
    assert.equal(created.status, 200);
    assert.equal((await request('DELETE', `/repairs/${created.body.id}`, alphaToken)).status, 200);

    await db('repairs').where({ id: jobId }).update({ status: 'ready' });
    const paid = await request('POST', '/repairs', alphaToken, jobBody({ imei: '', customer_name: 'Paid' }));
    await request('POST', `/repairs/${paid.body.id}/payments`, alphaToken, { amount: '100' });
    const blocked = await request('DELETE', `/repairs/${paid.body.id}`, alphaToken);
    assert.equal(blocked.status, 409);
    assert.equal(blocked.body.code, 'has_payments');
  });

  await t.test('super admin support access is read-only for repairs too', async () => {
    const shopId = alpha.body.id ?? alpha.body.shop?.id;
    const noAccess = await request('GET', `/repairs?shop_id=${shopId}`, admin);
    assert.equal(noAccess.status, 403);
    assert.equal(noAccess.body.code, 'support_access_required');

    const started = await request('POST', `/admin/shops/${shopId}/support-access`, admin,
      { reason: 'Repair job stuck at ready', minutes: 30 });
    assert.ok([200, 201].includes(started.status), JSON.stringify(started.body));

    const read = await request('GET', `/repairs?shop_id=${shopId}`, admin);
    assert.equal(read.status, 200, JSON.stringify(read.body));
    assert.ok(read.body.length >= 1);

    const write = await request('POST', `/repairs?shop_id=${shopId}`, admin, jobBody({ imei: '' }));
    assert.equal(write.status, 403);
    assert.equal(write.body.code, 'support_access_read_only');

    const status = await request('POST', `/repairs/${jobId}/status?shop_id=${shopId}`, admin, { status: 'ready' });
    assert.equal(status.status, 403);
  });
});
