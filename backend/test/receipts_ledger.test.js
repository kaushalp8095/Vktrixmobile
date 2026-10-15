// Customer-safe PDF receipt payloads and the auditable udhaar ledger.
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
  process.env.SQLITE_FILE = path.join(os.tmpdir(), `vktrix-receipts-${process.pid}.sqlite`);
  for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
}
process.env.JWT_SECRET = 'isolated-receipt-tests';
process.env.SUPERADMIN_USERNAME = 'superadmin';
process.env.SUPERADMIN_PASSWORD = 'AuditOnly@123';

const express = require('express');
const db = require('../src/db');
const migrate = require('../src/migrate');
const V = require('../src/validation');

const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';
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
  return r;
}

const buyBody = (imei, overrides = {}) => ({
  imei, brand: 'Apple', model: 'iPhone 13', ram: '4GB', storage: '128GB', color: 'Blue',
  condition: 'Good', accessories: 'Box, charger', buy_price: '30000', buy_date: '2026-10-01',
  seller_name: 'Phone Seller', seller_phone: '9876543210', seller_address: 'Mahesana',
  seller_id_type: 'Aadhaar', seller_id_no: 'SECRET-ID', customer_id_photo: PNG,
  notes: 'INTERNAL PURCHASE NOTE', ...overrides,
});

test('PDF payloads stay customer-safe; partial payments form a tenant-scoped ledger', async t => {
  await migrate();
  await db('sale_payments').del(); await db('sales').del(); await db('phones').del();
  await db('users').whereNot({ username: 'superadmin' }).del(); await db('shops').del();

  const app = express();
  app.use(express.json({ limit: '9mb' }));
  app.use('/api/auth', require('../src/routes/auth'));
  app.use('/api/admin', require('../src/routes/admin'));
  app.use('/api', require('../src/routes/shop'));
  app.use((err, req, res, next) => res.status(err.status || 500).json({ error: err.message }));
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}/api`;
  t.after(async () => {
    await new Promise(resolve => server.close(resolve));
    await db.destroy();
    if (!process.env.TEST_DATABASE_URL)
      for (const suffix of ['', '-shm', '-wal']) try { fs.unlinkSync(process.env.SQLITE_FILE + suffix); } catch {}
  });

  assert.equal(V.shopLogo(PNG), PNG);
  assert.throws(() => V.shopLogo('data:image/svg+xml;base64,AAAA'), /JPEG, PNG or WebP/);

  const admin = (await login('superadmin', 'AuditOnly@123')).body.token;
  const alpha = await request('POST', '/admin/shops', admin, {
    name: 'Alpha Mobiles', owner_name: 'A Owner', phone: '9876543210', address: 'Market Road', gst_no: '24ABCDE1234F1Z5',
    logo_data: PNG, username: 'alpha', password: 'Alpha@123',
  });
  const beta = await request('POST', '/admin/shops', admin, {
    name: 'Beta Mobiles', username: 'beta', password: 'Beta@123',
  });
  assert.equal(alpha.status, 200, JSON.stringify(alpha.body));
  assert.equal(beta.status, 200, JSON.stringify(beta.body));
  const alphaLogin = await login('alpha', 'Alpha@123');
  const alphaToken = alphaLogin.body.token;
  const betaToken = (await login('beta', 'Beta@123')).body.token;
  assert.equal(alphaLogin.body.user.shop.logo_data, PNG, 'shop logo is available to the app after login');

  const bought = await request('POST', '/buy', alphaToken, buyBody(IMEI_A));
  assert.equal(bought.status, 200, JSON.stringify(bought.body));

  const purchase = await request('GET', `/receipts/purchase/${bought.body.id}`, alphaToken);
  assert.equal(purchase.status, 200, JSON.stringify(purchase.body));
  assert.match(purchase.body.number, /^PUR-/);
  assert.equal(purchase.body.shop.logo_data, PNG);
  assert.equal(purchase.body.customer.name, 'Phone Seller');
  assert.equal(purchase.body.phone.imei, IMEI_A);
  assert.equal(purchase.body.amount, 30000);
  const purchaseJson = JSON.stringify(purchase.body);
  assert.doesNotMatch(purchaseJson, /SECRET-ID|INTERNAL PURCHASE NOTE|customer_id_photo|seller_id_no/);
  assert.equal((await request('GET', `/receipts/purchase/${bought.body.id}`, betaToken)).status, 404);

  const sold = await request('POST', '/sell', alphaToken, {
    phone_id: bought.body.id, sell_price: '36000', sell_date: '2026-10-02', customer_name: 'Buyer Name',
    customer_phone: '9988776655', customer_address: 'Station Road', payment_mode: 'upi',
    amount_received: '10000', warranty: '7 days shop warranty', notes: 'INTERNAL SALE NOTE',
  });
  assert.equal(sold.status, 200, JSON.stringify(sold.body));
  assert.equal(sold.body.payment_status, 'partial');
  assert.equal(sold.body.paid_amount, 10000);
  assert.equal(sold.body.balance_due, 26000);

  const receipt = await request('GET', `/receipts/sale/${sold.body.id}`, alphaToken);
  assert.equal(receipt.status, 200, JSON.stringify(receipt.body));
  assert.match(receipt.body.number, /^INV-/);
  assert.equal(receipt.body.amount, 36000);
  assert.equal(receipt.body.warranty, '7 days shop warranty');
  assert.equal(receipt.body.paid_amount, 10000);
  assert.equal(receipt.body.balance_due, 26000);
  const receiptJson = JSON.stringify(receipt.body);
  assert.doesNotMatch(receiptJson, /buy_price|profit|INTERNAL SALE NOTE|INTERNAL PURCHASE NOTE|customer_id_photo|SECRET-ID/);
  assert.equal((await request('GET', `/receipts/sale/${sold.body.id}`, betaToken)).status, 404);

  const sales = await request('GET', '/sales', alphaToken);
  assert.equal(sales.body[0].paid_amount, 10000);
  assert.equal(sales.body[0].balance_due, 26000);
  assert.equal(sales.body[0].payment_count, 1);

  let ledger = await request('GET', '/ledger', alphaToken);
  assert.equal(ledger.status, 200);
  assert.equal(ledger.body.summary.outstanding, 26000);
  assert.equal(ledger.body.summary.pending_count, 1);
  assert.equal(ledger.body.items[0].id, sold.body.id);
  assert.equal((await request('GET', '/ledger', betaToken)).body.items.length, 0);
  assert.equal((await request('GET', '/ledger?status=nope', alphaToken)).status, 400);

  let history = await request('GET', `/sales/${sold.body.id}/payments`, alphaToken);
  assert.equal(history.body.payments.length, 1);
  assert.equal(history.body.payments[0].amount, 10000);
  assert.equal(history.body.sale.notes, 'INTERNAL SALE NOTE', 'ledger detail may show internal notes in-app');
  assert.equal((await request('GET', `/sales/${sold.body.id}/payments`, betaToken)).status, 404);

  const tooMuch = await request('POST', `/sales/${sold.body.id}/payments`, alphaToken,
    { amount: '26000.01', payment_date: '2026-10-03', payment_mode: 'cash' });
  assert.equal(tooMuch.status, 400);
  assert.match(tooMuch.body.error, /balance/);
  const tooEarly = await request('POST', `/sales/${sold.body.id}/payments`, alphaToken,
    { amount: '1', payment_date: '2026-09-30', payment_mode: 'cash' });
  assert.equal(tooEarly.status, 400);
  assert.equal((await request('POST', `/sales/${sold.body.id}/payments`, betaToken,
    { amount: '1', payment_date: '2026-10-03', payment_mode: 'cash' })).status, 404);

  const part = await request('POST', `/sales/${sold.body.id}/payments`, alphaToken,
    { amount: '11000', payment_date: '2026-10-03', payment_mode: 'cash', note: 'Second instalment' });
  assert.equal(part.status, 200, JSON.stringify(part.body));
  assert.equal(part.body.payment_status, 'partial');
  assert.equal(part.body.balance_due, 15000);
  const final = await request('POST', `/sales/${sold.body.id}/payments`, alphaToken,
    { amount: '15000', payment_date: '2026-10-04', payment_mode: 'bank' });
  assert.equal(final.status, 200, JSON.stringify(final.body));
  assert.equal(final.body.payment_status, 'paid');
  assert.equal(final.body.balance_due, 0);

  ledger = await request('GET', '/ledger', alphaToken);
  assert.equal(ledger.body.summary.outstanding, 0);
  assert.equal(ledger.body.items.length, 0);
  const paidLedger = await request('GET', '/ledger?status=paid', alphaToken);
  assert.equal(paidLedger.body.items.length, 1);
  assert.equal(paidLedger.body.items[0].paid_amount, 36000);
  history = await request('GET', `/sales/${sold.body.id}/payments`, alphaToken);
  assert.deepEqual(history.body.payments.map(x => x.amount), [15000, 11000, 10000]);

  // Legacy clients omit amount_received: they keep the old fully-paid behaviour.
  const bought2 = await request('POST', '/buy', alphaToken, buyBody(IMEI_B, { customer_id_photo: '' }));
  const sold2 = await request('POST', '/sell', alphaToken,
    { phone_id: bought2.body.id, sell_price: '32000', sell_date: '2026-10-05', payment_mode: 'cash' });
  assert.equal(sold2.status, 200);
  assert.equal(sold2.body.payment_status, 'paid');

  const cancelled = await request('DELETE', `/sales/${sold.body.id}`, alphaToken);
  assert.equal(cancelled.status, 200);
  assert.equal(+(await db('sale_payments').where({ sale_id: sold.body.id }).count('* as n').first()).n, 0);
  assert.equal((await request('GET', `/receipts/sale/${sold.body.id}`, alphaToken)).status, 404);
});
