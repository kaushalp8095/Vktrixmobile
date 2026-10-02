// Sirf SUPER ADMIN: shops + unke login manage karna, TAC database import
const r = require('express').Router();
const bcrypt = require('bcryptjs');
const multer = require('multer');
const db = require('../db');
const { requireAuth, requireRole } = require('../auth');
const { wrap } = require('../util');
const V = require('../validation');
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
  const b = V.body(req);
  const data = V.shopData(b);
  const username = V.text(b.username, 'username', { required: true, max: 64 });
  if (!/^[A-Za-z0-9._-]{3,64}$/.test(username))
    return res.status(400).json({ error: 'username must be 3-64 letters, numbers, dot, underscore or hyphen' });
  const password = V.password(b.password);
  if (await db('users').where({ username }).first()) return res.status(409).json({ error: 'Username pehle se hai' });
  const id = await db.transaction(async trx => {
    const [row] = await trx('shops').insert(data).returning('id');
    const shopId = typeof row === 'object' ? row.id : row;
    await trx('users').insert({ username, name: data.owner_name || data.name, role: 'shop_admin', shop_id: shopId,
      password_hash: bcrypt.hashSync(password, 10), token_version: 0 });
    return shopId;
  });
  res.json({ id });
}));

r.put('/shops/:id', wrap(async (req, res) => {
  const id = V.id(req.params.id, 'shop id');
  const data = V.shopData(V.body(req), true);
  const changed = await db('shops').where({ id }).update(data);
  if (!changed) return res.status(404).json({ error: 'Shop nahi mila' });
  res.json({ ok: true });
}));

r.post('/shops/:id/reset-password', wrap(async (req, res) => {
  const shopId = V.id(req.params.id, 'shop id');
  const b = V.body(req);
  const password = V.password(b.password);
  const changed = await db('users').where({ shop_id: shopId, role: 'shop_admin' }).update({
    password_hash: bcrypt.hashSync(password, 10),
    token_version: db.raw('?? + 1', ['token_version']),
  });
  if (!changed) return res.status(404).json({ error: 'Shop owner login nahi mila' });
  res.json({ ok: true, sessions_revoked: true });
}));

r.delete('/shops/:id', wrap(async (req, res) => {
  const shopId = V.id(req.params.id, 'shop id');
  const exists = await db('shops').where({ id: shopId }).first();
  if (!exists) return res.status(404).json({ error: 'Shop nahi mila' });
  await db.transaction(async trx => {
    await trx('sales').where({ shop_id: shopId }).del();
    await trx('phones').where({ shop_id: shopId }).del();
    await trx('users').where({ shop_id: shopId }).del();
    await trx('shops').where({ id: shopId }).del();
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
