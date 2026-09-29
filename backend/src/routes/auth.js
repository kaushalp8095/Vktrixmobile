const r = require('express').Router();
const bcrypt = require('bcryptjs');
const db = require('../db');
const { sign, requireAuth } = require('../auth');
const { wrap } = require('../util');

r.post('/login', wrap(async (req, res) => {
  const { username, password } = req.body;
  const u = await db('users').where({ username }).first();
  if (!u || !u.active || !bcrypt.compareSync(password || '', u.password_hash))
    return res.status(401).json({ error: 'Galat username ya password' });
  let shop = null;
  if (u.shop_id) {
    shop = await db('shops').where({ id: u.shop_id }).first();
    if (!shop.active) return res.status(403).json({ error: 'Shop band hai. Admin se contact karein.' });
  }
  res.json({ token: sign(u), user: { id: u.id, name: u.name, username: u.username, role: u.role, shop } });
}));

r.post('/change-password', requireAuth, wrap(async (req, res) => {
  const { old_password, new_password } = req.body;
  if (!bcrypt.compareSync(old_password || '', req.user.password_hash)) return res.status(400).json({ error: 'Purana password galat hai' });
  if (!new_password || new_password.length < 6) return res.status(400).json({ error: 'Password kam se kam 6 character' });
  await db('users').where({ id: req.user.id }).update({ password_hash: bcrypt.hashSync(new_password, 10) });
  res.json({ ok: true });
}));
module.exports = r;
