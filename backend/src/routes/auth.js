const r = require('express').Router();
const bcrypt = require('bcryptjs');
const db = require('../db');
const { sign, requireAuth } = require('../auth');
const { wrap } = require('../util');
const V = require('../validation');
const { hit, reset, createLimiter } = require('../ratelimit');

// Brute-force protection. Pehle login par koi limit nahi thi: ek script raat bhar
// usernames/passwords try kar sakti thi. Ab do counters hain —
//   * per username: 10 attempts / 15 min (success par reset),
//   * per IP: 100 attempts / 15 min (shared NAT ke liye udaar).
// IP wala counter proxy IP ho sakta hai (agar TRUST_PROXY_HOPS set nahi), isliye
// asli suraksha per-username counter hai.
const LOGIN_WINDOW_MS = Number(process.env.AUTH_LOGIN_WINDOW_MS) || 15 * 60 * 1000;
const LOGIN_MAX = Number(process.env.AUTH_LOGIN_MAX) || 10;
const LOGIN_IP_MAX = Number(process.env.AUTH_IP_MAX) || 100;

// Unknown username par bhi bcrypt chalta hai, warna response time se pata chal
// jata hai ki username exist karta hai ya nahi (account enumeration).
// Ek hi dummy hash poore process ke liye — per request generate karna waste hai.
const DUMMY_HASH = bcrypt.hashSync('vktrix-dummy-password-not-a-real-account', 10);

function tooMany(res, retryAfter) {
  res.setHeader('Retry-After', String(retryAfter));
  return res.status(429).json({
    error: 'Bahut zyada galat koshish. 15 minute baad try karein.',
    code: 'login_rate_limited',
    retry_after_seconds: retryAfter,
  });
}

r.post('/login', wrap(async (req, res) => {
  const b = V.body(req);
  const username = V.text(b.username, 'username', { required: true, max: 64 });
  const userKey = username.toLowerCase();
  const userHit = hit({ name: 'login-user', key: userKey, windowMs: LOGIN_WINDOW_MS, max: LOGIN_MAX });
  const ipHit = hit({ name: 'login-ip', key: req.ip, windowMs: LOGIN_WINDOW_MS, max: LOGIN_IP_MAX });
  if (userHit.limited || ipHit.limited) {
    return tooMany(res, Math.max(userHit.limited ? userHit.retryAfter : 1, ipHit.limited ? ipHit.retryAfter : 1));
  }
  if (typeof b.password !== 'string' || Buffer.byteLength(b.password, 'utf8') > 72) {
    bcrypt.compareSync('', DUMMY_HASH);
    return res.status(401).json({ error: 'Galat username ya password' });
  }
  const u = await db('users').where({ username }).first();
  if (!u || !u.active) {
    bcrypt.compareSync(b.password, DUMMY_HASH); // same timing as a real wrong password
    return res.status(401).json({ error: 'Galat username ya password' });
  }
  if (!bcrypt.compareSync(b.password, u.password_hash))
    return res.status(401).json({ error: 'Galat username ya password' });
  let shop = null;
  if (u.shop_id) {
    shop = await db('shops').where({ id: u.shop_id }).first();
    if (!shop || !shop.active) return res.status(403).json({ error: 'Shop band hai. Admin se contact karein.' });
  }
  // Sahi login = galtiyan maaf.
  reset({ name: 'login-user', key: userKey });
  res.json({ token: sign(u), user: { id: u.id, name: u.name, username: u.username, role: u.role, shop } });
}));

r.post('/change-password', requireAuth, createLimiter({
  name: 'change-password',
  windowMs: 15 * 60 * 1000,
  max: Number(process.env.AUTH_PASSWORD_MAX) || 10,
  key: req => `u:${req.user?.id ?? req.ip}`,
  message: 'Bahut zyada password attempts. 15 minute baad try karein.',
  code: 'password_rate_limited',
}), wrap(async (req, res) => {
  const b = V.body(req);
  if (typeof b.old_password !== 'string' || Buffer.byteLength(b.old_password, 'utf8') > 72 ||
      !bcrypt.compareSync(b.old_password || '', req.user.password_hash))
    return res.status(400).json({ error: 'Purana password galat hai' });
  const newPassword = V.password(b.new_password, 'new_password');
  const changed = await db('users').where({ id: req.user.id, token_version: req.user.token_version ?? 0 }).update({
    password_hash: bcrypt.hashSync(newPassword, 10),
    token_version: db.raw('?? + 1', ['token_version']),
  });
  if (!changed) return res.status(409).json({ error: 'Account changed. Please log in again.' });
  res.json({ ok: true, session_revoked: true });
}));
module.exports = r;
