// Sirf SUPER ADMIN: shops + unke login manage karna, TAC database import
const r = require('express').Router();
const bcrypt = require('bcryptjs');
const multer = require('multer');
const db = require('../db');
const { requireAuth, requireRole } = require('../auth');
const { wrap } = require('../util');
r.use(requireAuth, requireRole('superadmin'));

r.get('/dashboard', wrap(async (req, res) => {
  const shops = await db('shops').count('* as c').first();
  const stock = await db('phones').where({ status: 'in_stock' }).count('* as c').sum('buy_price as v').first();
  const sales = await db('sales').count('* as c').sum('sell_price as v').first();
  res.json({ shops: +shops.c, stock_count: +stock.c, stock_value: +stock.v || 0, sales_count: +sales.c, sales_value: +sales.v || 0 });
}));

r.get('/shops', wrap(async (req, res) => {
  const shops = await db('shops').orderBy('id', 'desc');
  for (const s of shops) {
    s.login = await db('users').where({ shop_id: s.id, role: 'shop_admin' }).select('id', 'username', 'active').first();
    const st = await db('phones').where({ shop_id: s.id, status: 'in_stock' }).count('* as c').first();
    s.stock_count = +st.c;
  }
  res.json(shops);
}));

// Nayi shop + uska login ek saath
r.post('/shops', wrap(async (req, res) => {
  const { name, owner_name, phone, address, gst_no, username, password } = req.body;
  if (!name || !username || !password) return res.status(400).json({ error: 'Shop name, username, password zaroori hai' });
  if (await db('users').where({ username }).first()) return res.status(400).json({ error: 'Username pehle se hai' });
  const id = await db.transaction(async trx => {
    const [row] = await trx('shops').insert({ name, owner_name, phone, address, gst_no }).returning('id');
    const shopId = typeof row === 'object' ? row.id : row;
    await trx('users').insert({ username, name: owner_name || name, role: 'shop_admin', shop_id: shopId,
      password_hash: bcrypt.hashSync(password, 10) });
    return shopId;
  });
  res.json({ id });
}));

r.put('/shops/:id', wrap(async (req, res) => {
  const { name, owner_name, phone, address, gst_no, active } = req.body;
  await db('shops').where({ id: req.params.id }).update({ name, owner_name, phone, address, gst_no, active });
  res.json({ ok: true });
}));

r.post('/shops/:id/reset-password', wrap(async (req, res) => {
  const { password } = req.body;
  if (!password || password.length < 6) return res.status(400).json({ error: 'Password kam se kam 6 character' });
  await db('users').where({ shop_id: req.params.id }).update({ password_hash: bcrypt.hashSync(password, 10) });
  res.json({ ok: true });
}));

r.delete('/shops/:id', wrap(async (req, res) => {
  await db.transaction(async trx => {
    await trx('sales').where({ shop_id: req.params.id }).del();
    await trx('phones').where({ shop_id: req.params.id }).del();
    await trx('users').where({ shop_id: req.params.id }).del();
    await trx('shops').where({ id: req.params.id }).del();
  });
  res.json({ ok: true });
}));

// TAC CSV import. Columns: tac,brand,model[,ram,storage]
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 50 * 1024 * 1024 } });
r.post('/tac/import', upload.single('file'), wrap(async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'CSV file bhejein' });
  const lines = req.file.buffer.toString('utf8').split(/\r?\n/);
  let n = 0;
  for (const line of lines) {
    const c = line.split(',').map(x => x.trim().replace(/^"|"$/g, ''));
    if (!/^\d{8}$/.test(c[0])) continue;
    const row = { tac: c[0], brand: c[1] || null, model: c[2] || null, ram: c[3] || null, storage: c[4] || null };
    await db('tac_models').insert(row).onConflict('tac').merge();
    n++;
  }
  res.json({ imported: n });
}));
module.exports = r;
