// API-boundary validation: never rely only on Flutter form validators.
const { validImei, today } = require('./util');
const fail = message => { throw Object.assign(new Error(message), { status: 400 }); };
function body(req) {
  const b = req.body;
  if (!b || typeof b !== 'object' || Array.isArray(b)) fail('JSON object body required');
  return b;
}
function text(value, field, { required = false, max = 255 } = {}) {
  if (value == null) { if (required) fail(`${field} required`); return null; }
  if (typeof value !== 'string') fail(`${field} must be text`);
  const v = value.trim();
  if (required && !v) fail(`${field} required`);
  if (v.length > max) fail(`${field} too long (max ${max})`);
  return v || null;
}
function id(value, field = 'id') {
  if (!['string', 'number'].includes(typeof value) || !/^[1-9]\d*$/.test(String(value))) fail(`${field} must be a positive integer`);
  const n = Number(value);
  if (!Number.isSafeInteger(n) || n > 2147483647) fail(`${field} invalid`);
  return n;
}
function money(value, field) {
  if (!['string', 'number'].includes(typeof value)) fail(`${field} required`);
  const s = String(value).trim();
  if (!/^\d{1,10}(\.\d{1,2})?$/.test(s) || !Number.isFinite(Number(s)) || Number(s) <= 0)
    fail(`${field} must be positive, max 9999999999.99, with at most 2 decimal places`);
  // Preserve exact decimal text for PostgreSQL NUMERIC rather than coercing NaN/Infinity.
  const [whole, fraction = ''] = s.split('.');
  return `${Number(whole)}.${fraction.padEnd(2, '0')}`;
}
function date(value, field) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) fail(`${field} must be YYYY-MM-DD`);
  const d = new Date(value + 'T00:00:00Z');
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== value || value < '1900-01-01') fail(`${field} invalid date`);
  return value;
}
function imei(value, field = 'imei', required = true) {
  const v = text(value, field, { required, max: 15 });
  if (v && !validImei(v)) fail(`${field} must be a valid 15-digit IMEI`);
  return v;
}
function choice(value, field, allowed) {
  const v = text(value, field);
  if (v && !allowed.includes(v)) fail(`${field} invalid`);
  return v;
}
function mobile(value, field) {
  const v = text(value, field, { max: 32 });
  if (v && (!/^\+?[\d ()-]+$/.test(v) || !/^\d{7,15}$/.test(v.replace(/\D/g, '')))) fail(`${field} invalid phone number`);
  return v;
}
function password(value, field = 'password') {
  if (typeof value !== 'string' || value.length < 6 || Buffer.byteLength(value, 'utf8') > 72)
    fail(`${field} must be at least 6 characters and at most 72 UTF-8 bytes`);
  return value;
}
const phoneFields = ['brand', 'model', 'ram', 'storage', 'color', 'condition', 'accessories', 'buy_price', 'buy_date',
  'seller_name', 'seller_phone', 'seller_id_type', 'seller_id_no', 'seller_address', 'notes', 'imei2'];
function phoneData(b, partial = false) {
  const out = {};
  for (const k of phoneFields) {
    if (partial && !Object.hasOwn(b, k)) continue;
    if (k === 'buy_price') out[k] = money(b[k], k);
    else if (k === 'buy_date') out[k] = date(b[k] || today(), k);
    else if (k === 'imei2') out[k] = imei(b[k], k, false);
    else if (k === 'condition') out[k] = choice(b[k], k, ['Excellent', 'Good', 'Fair', 'Faulty']);
    else if (k === 'seller_id_type') out[k] = choice(b[k], k, ['Aadhaar', 'PAN', 'Voter ID', 'Driving Licence']);
    else if (k === 'seller_phone') out[k] = mobile(b[k], k);
    else out[k] = text(b[k], k, { required: k === 'model', max: k === 'notes' ? 5000 : 255 });
  }
  if (!partial) {
    out.imei = imei(b.imei);
    if (out.imei === out.imei2) fail('imei2 must differ from imei');
  }
  if (partial && !Object.keys(out).length) fail('No editable fields supplied');
  return out;
}
function saleData(b) {
  const out = { phone_id: id(b.phone_id, 'phone_id'), sell_price: money(b.sell_price, 'sell_price'),
    sell_date: date(b.sell_date || today(), 'sell_date'),
    payment_mode: choice(b.payment_mode, 'payment_mode', ['cash', 'upi', 'card', 'credit', 'emi']) || 'cash' };
  for (const k of ['customer_name', 'customer_address', 'warranty', 'notes']) out[k] = text(b[k], k, { max: k === 'notes' ? 5000 : 255 });
  out.customer_phone = mobile(b.customer_phone, 'customer_phone');
  return out;
}
function range(query, defaults = [today(), today()]) {
  const from = date(query.from ?? defaults[0], 'from'), to = date(query.to ?? defaults[1], 'to');
  if (from > to) fail('from must not be after to');
  return { from, to };
}
function shopData(b, partial = false) {
  const out = {};
  for (const k of ['name', 'owner_name', 'phone', 'address', 'gst_no']) {
    if (partial && !Object.hasOwn(b, k)) continue;
    out[k] = k === 'phone' ? mobile(b[k], k) : text(b[k], k, { required: k === 'name' });
  }
  if (Object.hasOwn(b, 'active')) {
    // SQLite responses encode booleans as 0/1; accept those alongside JSON booleans.
    if (![true, false, 0, 1].includes(b.active)) fail('active must be boolean');
    out.active = Boolean(b.active);
  }
  if (partial && !Object.keys(out).length) fail('No editable fields supplied');
  return out;
}
module.exports = { fail, body, text, id, money, date, imei, password, phoneData, saleData, range, shopData, choice };
