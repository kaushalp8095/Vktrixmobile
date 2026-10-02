const r = require('express').Router();
const bcrypt = require('bcryptjs');
const db = require('../db');
const { sign, requireAuth } = require('../auth');
const { wrap } = require('../util');
const V = require('../validation');

r.post('/login', wrap(async (req, res) => {
  const b = V.body(req);
  const username = V.text(b.username, 'username', { required: true, max: 64 });
  if (typeof b.password !== 'string' || Buffer.byteLength(b.password, 'utf8') > 72)
    return res.status(401).json({ error: 'Galat username ya password' });
  const u = await db('users').where({ username }).first();
  if (!u || !u.active || !bcrypt.compareSync(b.password, u.password_hash))
    return res.status(401).json({ error: 'Galat username ya password' });
  let shop = null;
  if (u.shop_id) {
    shop = await db('shops').where({ id: u.shop_id }).first();
    if (!shop || !shop.active) return res.status(403).json({ error: 'Shop band hai. Admin se contact karein.' });
  }
  res.json({ token: sign(u), user: { id: u.id, name: u.name, username: u.username, role: u.role, shop } });
}));

r.post('/change-password', requireAuth, wrap(async (req, res) => {
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
