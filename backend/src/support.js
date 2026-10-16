// TEMPORARY SUPPORT ACCESS (Super Admin)
//
// Super Admin ke paas shop ke business data (stock, IMEI, sales, profit, payment
// ledger, customer/ID details) ka **koi default access nahi** hai. Wo sirf ek
// time-boxed support session ke andar dekh sakta hai, jo:
//   * ek reason ke saath shuru hoti hai (min 10 characters),
//   * kuch minute/hours me khud khatam ho jati hai,
//   * **read-only** hai (shop ka data change nahi hota),
//   * shop owner ko app me dikhti hai — reason, kitni baar data dekha gaya
//     (reads) aur contact reveal ke saath.
//
// Is file ke helpers hi wo single source hain: routes/shop.js sirf inse pooch
// kar shop data deta hai, aur routes/admin.js inse sessions banata/khatam karta hai.
const db = require('./db');

const MIN_MINUTES = 5;
const MAX_MINUTES = 240;
const DEFAULT_MINUTES = 30;
const REASON_MIN = 10;
const REASON_MAX = 300;
// Ek screen kai requests bhejti hai. 1 minute ke andar ki reads ko ek "view" ginte
// hain (warna log bekaar ke 40 rows dikhayega).
const READ_COALESCE_MS = 60 * 1000;

const num = value => (value == null ? 0 : Number(value));
const nowMs = () => Date.now();

function fail(message, status) { throw Object.assign(new Error(message), { status }); }

// Contact ko dikhane layak rakhta hai par number chhupata hai:
// 9876543210 -> 98•••••210. Sirf pehle 2 aur aakhri 3 characters rehte hain.
function maskPhone(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return null;
  const chars = [...raw];
  const n = chars.length;
  if (n <= 4) return '•'.repeat(n);
  const head = n >= 8 ? 2 : 1;
  const tail = n >= 8 ? 3 : 2;
  const hidden = n - head - tail;
  if (hidden <= 0) return `${chars[0]}${'•'.repeat(n - 1)}`;
  return `${chars.slice(0, head).join('')}${'•'.repeat(hidden)}${chars.slice(n - tail).join('')}`;
}

function normalizeMinutes(value) {
  if (value == null || value === '') return DEFAULT_MINUTES;
  const minutes = Math.round(Number(value));
  if (!Number.isFinite(minutes) || minutes < MIN_MINUTES || minutes > MAX_MINUTES)
    fail(`minutes ${MIN_MINUTES}-${MAX_MINUTES} ke beech chahiye`, 400);
  return minutes;
}

function normalizeReason(value) {
  const reason = String(value ?? '').trim().replace(/\s+/g, ' ');
  if (reason.length < REASON_MIN)
    fail(`Reason kam se kam ${REASON_MIN} characters ka likhein — kya dekha jayega aur kyun`, 400);
  if (reason.length > REASON_MAX) fail(`Reason bahut lamba hai (max ${REASON_MAX})`, 400);
  return reason;
}

// Purane sessions ko 'expired' mark karta hai taaki log saaf rahe.
async function closeExpired(shopId = null, runner = db) {
  const q = runner('support_access').whereNull('ended_at_ms').andWhere('expires_at_ms', '<=', nowMs());
  if (shopId) q.andWhere({ shop_id: shopId });
  return q.update({ ended_at_ms: nowMs(), end_reason: 'expired' });
}

// Shop ke liye abhi chal raha session (chaho to us admin ka). Koi nahi to null.
async function activeGrant(shopId, userId = null, runner = db) {
  const q = runner('support_access').where({ shop_id: shopId }).whereNull('ended_at_ms');
  if (userId != null) q.andWhere({ user_id: userId });
  const row = await q.orderBy('id', 'desc').first();
  if (!row || num(row.expires_at_ms) <= nowMs()) return null;
  return row;
}

async function getById(id, runner = db) { return runner('support_access').where({ id }).first(); }

function shape(row) {
  const now = nowMs();
  const expires = num(row.expires_at_ms);
  const ended = row.ended_at_ms == null ? null : num(row.ended_at_ms);
  const status = ended != null ? (row.end_reason === 'expired' ? 'expired' : 'ended')
    : expires <= now ? 'expired' : 'active';
  return {
    id: row.id,
    shop_id: row.shop_id,
    shop_name: row.shop_name ?? null,
    admin_name: row.admin_name ?? 'Super Admin',
    admin_username: row.admin_username ?? null,
    reason: row.reason,
    minutes: num(row.minutes),
    status,
    end_reason: row.end_reason ?? null,
    started_at_ms: num(row.started_at_ms),
    expires_at_ms: expires,
    ended_at_ms: ended,
    // Server se hi bacha hua time bhejte hain: phone ki clock galat ho to bhi countdown sahi rahe.
    expires_in_ms: status === 'active' ? Math.max(0, expires - now) : 0,
    reads: num(row.read_count),
    first_read_ms: row.first_read_ms == null ? null : num(row.first_read_ms),
    last_read_ms: row.last_read_ms == null ? null : num(row.last_read_ms),
    contact_reveals: num(row.contact_reveals),
    last_reveal_ms: row.last_reveal_ms == null ? null : num(row.last_reveal_ms),
    created_at: row.created_at ?? null,
  };
}

// Naya session. Ek shop par ek hi active session ho sakta hai.
async function start({ shopId, userId, reason, minutes }) {
  const cleanReason = normalizeReason(reason);
  const mins = normalizeMinutes(minutes);
  await closeExpired(shopId);
  const running = await activeGrant(shopId);
  if (running)
    fail('Is shop ka support access pehle se chal raha hai. Naya shuru karne se pehle use end karein.', 409);
  const started = nowMs();
  const [row] = await db('support_access').insert({
    shop_id: shopId,
    user_id: userId ?? null,
    reason: cleanReason,
    minutes: mins,
    started_at_ms: started,
    expires_at_ms: started + mins * 60 * 1000,
    read_count: 0,
    contact_reveals: 0,
  }).returning('id');
  const id = typeof row === 'object' && row !== null ? row.id : row;
  return shape(await getById(id));
}

// Session khatam karna (admin ne khud, ya shop owner ne rok diya).
async function end(id, userId = null, endReason = 'admin_ended') {
  const changed = await db('support_access').where({ id }).whereNull('ended_at_ms')
    .update({ ended_at_ms: nowMs(), ended_by: userId ?? null, end_reason: endReason });
  return changed > 0;
}

// Shop data padha gaya — log me ginti aur aakhri time likhta hai.
async function markRead(grant) {
  const now = nowMs();
  const last = num(grant.last_read_ms);
  if (last && now - last < READ_COALESCE_MS) return { reads: num(grant.read_count), counted: false };
  const reads = num(grant.read_count) + 1;
  await db('support_access').where({ id: grant.id })
    .update({ read_count: reads, last_read_ms: now, first_read_ms: grant.first_read_ms == null ? now : num(grant.first_read_ms) });
  return { reads, counted: true };
}

// Pura contact number dikhaya gaya (masked ko kholein) — ye bhi log hota hai.
async function logReveal(grant) {
  const now = nowMs();
  const reveals = num(grant.contact_reveals) + 1;
  await db('support_access').where({ id: grant.id }).update({ contact_reveals: reveals, last_reveal_ms: now });
  return { contact_reveals: reveals };
}

// Access log: kaun, kis shop ka, kab, kyun, kitna dekha.
async function list({ shopId = null, limit = 50 } = {}) {
  await closeExpired(shopId);
  const q = db('support_access as sa')
    .leftJoin('shops as sh', 'sh.id', 'sa.shop_id')
    .leftJoin('users as u', 'u.id', 'sa.user_id')
    .select('sa.*', 'sh.name as shop_name', 'u.name as admin_name', 'u.username as admin_username')
    .orderBy('sa.id', 'desc')
    .limit(Math.min(Math.max(Number(limit) || 50, 1), 200));
  if (shopId) q.where('sa.shop_id', shopId);
  const rows = await q;
  return rows.map(shape);
}

// Shop list ke liye ek chhota summary: active session aur 30 din ka total.
async function summaryByShop() {
  await closeExpired();
  const rows = await db('support_access').select('shop_id', 'ended_at_ms', 'expires_at_ms', 'reason');
  const now = nowMs();
  const out = new Map();
  for (const row of rows) {
    const id = Number(row.shop_id);
    const entry = out.get(id) ?? { active: null, total: 0 };
    entry.total += 1;
    if (row.ended_at_ms == null && num(row.expires_at_ms) > now) {
      if (!entry.active || num(row.expires_at_ms) > num(entry.active.expires_at_ms))
        entry.active = row;
    }
    out.set(id, entry);
  }
  for (const entry of out.values()) {
    entry.active = entry.active
      ? { reason: entry.active.reason, expires_in_ms: Math.max(0, num(entry.active.expires_at_ms) - now) }
      : null;
  }
  return out;
}

module.exports = { MIN_MINUTES, MAX_MINUTES, DEFAULT_MINUTES, maskPhone, normalizeMinutes, normalizeReason,
  closeExpired, activeGrant, getById, shape, start, end, markRead, logReveal, list, summaryByShop };
