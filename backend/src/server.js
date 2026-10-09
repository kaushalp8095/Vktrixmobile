require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const migrate = require('./migrate');

const app = express();
// 8mb: ID-proof photos are posted as base64 data URLs (~200-350 KB each, 3 MB cap).
app.use(helmet()); app.use(cors()); app.use(express.json({ limit: '8mb' }));
app.get('/', (req, res) => res.json({ app: 'Mobile Shop API', ok: true }));
app.use('/api/auth', require('./routes/auth'));
app.use('/api/admin', require('./routes/admin'));
app.use('/api', require('./routes/shop'));
app.use((err, req, res, next) => { console.error(err); res.status(err.status || 500).json({ error: err.message || 'Server error' }); });

const PORT = process.env.PORT || 4000;
migrate()
  .then(() => app.listen(PORT, '0.0.0.0', () => console.log(`API running on :${PORT}`)))
  .catch(err => {
    console.error('\n❌ DATABASE SE CONNECT NAHI HO PAYA:', err.message);
    if (!process.env.DATABASE_URL) console.error('👉 DATABASE_URL set nahi hai.');
    else if (err.code === 'ENOTFOUND') console.error('👉 DATABASE_URL galat hai. Render database page se "Internal Database URL" copy karke daalein.');
    else if (err.code === '28P01') console.error('👉 Database ka password galat hai.');
    process.exit(1);
  });
