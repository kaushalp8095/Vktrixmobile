const jwt = require('jsonwebtoken');
const db = require('./db');
const SECRET = () => process.env.JWT_SECRET || 'dev_secret';

const sign = u => jwt.sign({ id: u.id, role: u.role, shop_id: u.shop_id }, SECRET(), { expiresIn: '30d' });

async function requireAuth(req, res, next) {
  try {
    const token = (req.headers.authorization || '').replace('Bearer ', '');
    const p = jwt.verify(token, SECRET());
    const user = await db('users').where({ id: p.id, active: true }).first();
    if (!user) return res.status(401).json({ error: 'User inactive' });
    if (user.shop_id) {
      const shop = await db('shops').where({ id: user.shop_id }).first();
      if (!shop || !shop.active) return res.status(403).json({ error: 'Shop band hai. Admin se contact karein.' });
    }
    req.user = user; next();
  } catch { res.status(401).json({ error: 'Login required' }); }
}
const requireRole = (...roles) => (req, res, next) =>
  roles.includes(req.user.role) ? next() : res.status(403).json({ error: 'Permission nahi hai' });

module.exports = { sign, requireAuth, requireRole };
