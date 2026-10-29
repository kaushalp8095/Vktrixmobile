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
function decimalMoney(value, field, { allowZero = false } = {}) {
  if (!['string', 'number'].includes(typeof value)) fail(`${field} required`);
  const s = String(value).trim();
  const n = Number(s);
  if (!/^\d{1,10}(\.\d{1,2})?$/.test(s) || !Number.isFinite(n) || (allowZero ? n < 0 : n <= 0)) {
    const kind = allowZero ? 'zero or positive' : 'positive';
    fail(`${field} must be ${kind}, max 9999999999.99, with at most 2 decimal places`);
  }
  // Preserve exact decimal text for PostgreSQL NUMERIC rather than coercing NaN/Infinity.
  const [whole, fraction = ''] = s.split('.');
  return `${Number(whole)}.${fraction.padEnd(2, '0')}`;
}
function money(value, field) { return decimalMoney(value, field); }
function moneyOrZero(value, field) { return decimalMoney(value, field, { allowZero: true }); }
function cents(value) { return Math.round(Number(value) * 100); }
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
// NIST SP 800-63B: lambai hi asli suraksha hai (8+). Pehle 6 tha — brute force
// ke liye bahut chhota. Purane passwords band nahi hote; sirf naye set karte
// waqt lagoo hota hai (change-password / admin reset / nayi shop).
function password(value, field = 'password') {
  if (typeof value !== 'string' || value.length < 8 || Buffer.byteLength(value, 'utf8') > 72)
    fail(`${field} must be at least 8 characters and at most 72 UTF-8 bytes`);
  return value;
}

// Accepted proofs of identity for the person the phone is bought from.
const ID_TYPES = ['Aadhaar', 'PAN', 'Voter ID', 'Driving Licence', 'Visiting Card'];

// ID photos are sent as base64 data URLs. Keep the cap below the 9 MB JSON
// limit per side for older clients; new clients target 100 KB per photo.
// Two maximum-size photos including base64 must fit the JSON request limit.
const ID_PHOTO_MAX_BYTES = 3 * 1024 * 1024;
const SHOP_LOGO_MAX_BYTES = 768 * 1024;

// Accepts a `data:image/...;base64,...` URL, or null/empty to clear it.
function imageDataUrl(value, field, maxBytes) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string') fail(`${field} must be a data URL`);
  // Check the length before running the regex on what could be a huge string.
  const maxChars = Math.ceil((maxBytes * 4) / 3) + 64;
  const maxLabel = maxBytes >= 1024 * 1024
    ? `${Math.round(maxBytes / (1024 * 1024))}MB` : `${Math.round(maxBytes / 1024)}KB`;
  if (value.length > maxChars) fail(`${field} is too large (max ${maxLabel})`);
  if (!/^data:image\/(?:jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(value))
    fail(`${field} must be a JPEG, PNG or WebP data URL`);
  const encoded = value.slice(value.indexOf(',') + 1);
  if (Buffer.from(encoded, 'base64').length > maxBytes)
    fail(`${field} is too large (max ${maxLabel})`);
  return value;
}
function idPhoto(value, field = 'customer_id_photo') {
  return imageDataUrl(value, field, ID_PHOTO_MAX_BYTES);
}
function shopLogo(value) { return imageDataUrl(value, 'logo_data', SHOP_LOGO_MAX_BYTES); }

const phoneFields = ['brand', 'model', 'ram', 'storage', 'color', 'condition', 'accessories', 'buy_price', 'buy_date',
  'seller_name', 'seller_phone', 'seller_id_type', 'seller_id_no', 'seller_address', 'notes', 'imei2',
  'serial_number', 'customer_id_photo', 'customer_id_photo_back'];
function phoneData(b, partial = false) {
  const out = {};
  for (const k of phoneFields) {
    if (partial && !Object.hasOwn(b, k)) continue;
    if (k === 'buy_price') out[k] = money(b[k], k);
    else if (k === 'buy_date') out[k] = date(b[k] || today(), k);
    else if (k === 'imei2') out[k] = imei(b[k], k, false);
    else if (k === 'condition') out[k] = choice(b[k], k, ['Excellent', 'Good', 'Fair', 'Faulty']);
    else if (k === 'seller_id_type') out[k] = choice(b[k], k, ID_TYPES);
    else if (k === 'seller_phone') out[k] = mobile(b[k], k);
    else if (k === 'serial_number') out[k] = text(b[k], k, { max: 64 });
    else if (k === 'customer_id_photo' || k === 'customer_id_photo_back') out[k] = idPhoto(b[k], k);
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
    payment_mode: choice(b.payment_mode, 'payment_mode', ['cash', 'upi', 'card', 'bank', 'credit', 'emi']) || 'cash' };
  for (const k of ['customer_name', 'customer_address', 'warranty', 'notes']) out[k] = text(b[k], k, { max: k === 'notes' ? 5000 : 255 });
  out.customer_id_type = choice(b.customer_id_type, 'customer_id_type', ID_TYPES);
  out.customer_id_photo = idPhoto(b.customer_id_photo, 'customer_id_photo');
  out.customer_id_photo_back = idPhoto(b.customer_id_photo_back, 'customer_id_photo_back');
  out.customer_phone = mobile(b.customer_phone, 'customer_phone');
  // Old clients did not send amount_received and treated a sale as fully paid.
  // A credit sale remains unpaid by default; new clients always send this field.
  out.amount_received = Object.hasOwn(b, 'amount_received')
    ? moneyOrZero(b.amount_received, 'amount_received')
    : out.payment_mode === 'credit' ? '0.00' : out.sell_price;
  if (cents(out.amount_received) > cents(out.sell_price)) fail('amount_received cannot exceed sell_price');
  return out;
}
function paymentData(b) {
  const out = {
    amount: money(b.amount, 'amount'),
    payment_date: date(b.payment_date || today(), 'payment_date'),
    payment_mode: choice(b.payment_mode, 'payment_mode', ['cash', 'upi', 'card', 'bank', 'other']) || 'cash',
    note: text(b.note, 'note', { max: 500 }),
  };
  return out;
}
// ---------- REPAIRS ----------
// Job ka status flow ek hi jagah: kaun se status se kahan ja sakte hain.
// delivered aur cancelled terminal hain (delivery ke baad wapas nahi).
const REPAIR_STATUSES = ['received', 'repairing', 'ready', 'hold', 'delivered', 'cancelled'];
const REPAIR_FLOW = {
  received: ['repairing', 'ready', 'hold', 'cancelled'],
  repairing: ['ready', 'hold', 'cancelled'],
  hold: ['repairing', 'ready', 'cancelled'],
  ready: ['delivered', 'repairing', 'hold', 'cancelled'],
  delivered: [],
  cancelled: ['received'],
};
function repairStatus(value, field = 'status') {
  const v = text(value, field, { required: true, max: 24 });
  if (!REPAIR_STATUSES.includes(v)) fail(`${field} invalid`);
  return v;
}
/// received/cancelled ko chhod kar baaki status "khula" hain (workshop me phone).
const REPAIR_OPEN_STATUSES = ['received', 'repairing', 'ready', 'hold'];
function repairData(b, partial = false) {
  const out = {};
  const textFields = {
    customer_name: 255, customer_phone: 32, customer_address: 500,
    brand: 120, model: 120, serial_number: 64, color: 64, accessories: 255,
    complaint: 2000, diagnosis: 2000, notes: 5000, device_lock_note: 255, parts_note: 500,
  };
  for (const [k, max] of Object.entries(textFields)) {
    if (partial && !Object.hasOwn(b, k)) continue;
    const required = k === 'customer_name' || k === 'complaint';
    if (k === 'customer_phone') out[k] = mobile(b[k], k);
    else if (k === 'device_lock_note') out[k] = text(b[k], k, { max });
    else out[k] = text(b[k], k, { required, max });
  }
  for (const k of ['imei', 'imei2']) {
    if (partial && !Object.hasOwn(b, k)) continue;
    out[k] = imei(b[k], k, false);        // optional — feature phone me IMEI nahi hota
  }
  for (const k of ['estimate', 'service_charge', 'parts_cost']) {
    if (partial && !Object.hasOwn(b, k)) continue;
    out[k] = moneyOrZero(b[k] ?? 0, k);   // 0 allowed: free checkup
  }
  if (!partial || Object.hasOwn(b, 'received_at')) out.received_at = date(b.received_at || today(), 'received_at');
  if (!partial || Object.hasOwn(b, 'promised_date')) {
    out.promised_date = b.promised_date ? date(b.promised_date, 'promised_date') : null;
    if (out.promised_date && out.received_at && out.promised_date < out.received_at)
      fail('promised_date cannot be before received_at');
  }
  if (!partial || Object.hasOwn(b, 'warranty_days')) {
    if (b.warranty_days == null || b.warranty_days === '') out.warranty_days = null;
    else {
      const n = Number(b.warranty_days);
      if (!Number.isInteger(n) || n < 0 || n > 3650) fail('warranty_days must be 0-3650');
      out.warranty_days = n;
    }
  }
  if (partial && !Object.hasOwn(b, 'phone_id')) { /* leave as is */ }
  else if (b.phone_id != null && b.phone_id !== '') out.phone_id = id(b.phone_id, 'phone_id');
  else if (Object.hasOwn(b, 'phone_id')) out.phone_id = null;
  if (!partial) {
    // Contact zaroori hai taaki deliver/reminder ho sake — siwaye shop ke apne
    // stock phone ke (case B), jahan "customer" khud dukaan hai.
    if (!out.customer_phone && !out.customer_address && !out.phone_id)
      fail('Customer mobile or address is required to contact them later');
    if (out.imei && out.imei === out.imei2) fail('imei2 must differ from imei');
  }
  if (partial && !Object.keys(out).length) fail('No editable fields supplied');
  return out;
}
function repairPaymentData(b) {
  return {
    amount: money(b.amount, 'amount'),
    payment_date: date(b.payment_date || today(), 'payment_date'),
    payment_mode: choice(b.payment_mode, 'payment_mode', ['cash', 'upi', 'card', 'bank', 'other']) || 'cash',
    note: text(b.note, 'note', { max: 500 }),
    kind: choice(b.kind, 'kind', ['advance', 'payment', 'refund']) || 'payment',
  };
}
function range(query, defaults = [today(), today()]) {
  const from = date(query.from ?? defaults[0], 'from'), to = date(query.to ?? defaults[1], 'to');
  if (from > to) fail('from must not be after to');
  return { from, to };
}
function shopData(b, partial = false) {
  const out = {};
  for (const k of ['name', 'owner_name', 'phone', 'address', 'gst_no', 'logo_data']) {
    if (partial && !Object.hasOwn(b, k)) continue;
    if (k === 'phone') out[k] = mobile(b[k], k);
    else if (k === 'logo_data') out[k] = shopLogo(b[k]);
    else out[k] = text(b[k], k, { required: k === 'name' });
  }
  if (Object.hasOwn(b, 'active')) {
    // SQLite responses encode booleans as 0/1; accept those alongside JSON booleans.
    if (![true, false, 0, 1].includes(b.active)) fail('active must be boolean');
    out.active = Boolean(b.active);
  }
  if (partial && !Object.keys(out).length) fail('No editable fields supplied');
  return out;
}
module.exports = { fail, body, text, id, money, moneyOrZero, cents, date, imei, password, idPhoto, shopLogo,
  ID_TYPES, ID_PHOTO_MAX_BYTES, SHOP_LOGO_MAX_BYTES, phoneData, saleData, paymentData, range, shopData, choice,
  REPAIR_STATUSES, REPAIR_OPEN_STATUSES, REPAIR_FLOW, repairStatus, repairData, repairPaymentData };
