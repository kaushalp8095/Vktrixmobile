require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const migrate = require('./migrate');
const { createLimiter } = require('./ratelimit');

/// Poora app bana kar deta hai (listen ke bina) — isse security middleware ko
/// tests bhi wahi use karte hain jo production me chalta hai.
function createApp() {
  const app = express();

  // Render (aur Cloudflare/Vercel) ke peeche asli client IP `X-Forwarded-For` me
  // aata hai. Iske bina `req.ip` har request me proxy ka hota — rate limit sab
  // users ke liye ek hi bucket ban jata. Kitne trusted hops hain wo env se aata
  // hai (Render: 1). Zyada hops maan lena XFF spoofing ko khol deta hai, isliye
  // default 0 (koi proxy nahi).
  const hops = Number(process.env.TRUST_PROXY_HOPS ?? process.env.TRUST_PROXY ?? 0);
  if (Number.isFinite(hops) && hops > 0) app.set('trust proxy', hops);

  app.use(helmet());
  // Mobile app `Origin` header hi nahi bhejta, isliye CORS ki zaroorat nahi. Pehle
  // `cors()` sab origins ko allow karta tha — kisi bhi website ke JS se API hit ho
  // sakti thi. Browser client chahiye to CORS_ORIGINS me exact origins likhein.
  const origins = (process.env.CORS_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
  app.use(cors({ origin: origins.length ? origins : false }));

  // JSON body ka limit 9 MB hai (ID photos / logo), par ye limit sirf un routes par
  // hona chahiye jo photos leti hain. Login jaisa public endpoint 9 MB body parse
  // karega to ek script memory bhar sakti hai — isliye Content-Length dekh kar
  // bade body wahi reject kar dete hain. (Chunked body 9 MB cap se hi ruk-ti hai.)
  const SMALL_BODY_MAX = 128 * 1024;
  const LARGE_JSON_ROUTES = [
    /^\/api\/buy\/?$/,
    /^\/api\/sell\/?$/,
    /^\/api\/phones\/\d+\/?$/,
    /^\/api\/admin\/shops(\/\d+)?\/?$/,
  ];
  app.use((req, res, next) => {
    if (!['POST', 'PUT', 'PATCH'].includes(req.method)) return next();
    const type = String(req.headers['content-type'] || '');
    if (type.startsWith('multipart/form-data')) return next(); // multer ka apna 50 MB cap hai
    const length = Number(req.headers['content-length']);
    if (!Number.isFinite(length) || length <= SMALL_BODY_MAX) return next();
    if (LARGE_JSON_ROUTES.some(re => re.test(req.path))) return next();
    return res.status(413).json({ error: 'Request body is too large for this endpoint.', code: 'body_too_large' });
  });
  app.use(express.json({ limit: '9mb' }));

  // Health check (Render ise hit karta hai) — rate limit se pehle.
  app.get('/', (req, res) => res.json({ app: 'Mobile Shop API', ok: true }));

  // Customer data (IMEI, sales, ID photos) kabhi kisi proxy/browser cache me na baithe.
  app.use('/api', (req, res, next) => { res.setHeader('Cache-Control', 'no-store'); next(); });

  // API-wide cap: scraping aur accidental loops ko rokta hai. Auth endpoints ka
  // apna, bahut strict limiter alag hai (routes/auth.js).
  app.use(createLimiter({
    name: 'api-global',
    windowMs: Number(process.env.RATE_LIMIT_WINDOW_MS) || 60 * 1000,
    max: Number(process.env.RATE_LIMIT_MAX) || 1000,
  }));

  app.use('/api/auth', require('./routes/auth'));
  app.use('/api/admin', require('./routes/admin'));
  app.use('/api', require('./routes/shop'));

  app.use((err, req, res, next) => {
    if (res.headersSent) return next(err);
    const status = Number(err.status || err.statusCode) || 500;
    // 5xx = hamari galti. Stack/sql error server log me jaata hai, client ko nahi —
    // warna DB path, column names aur library internals leak hote hain.
    if (status >= 500) console.error(`[${req.method} ${req.originalUrl}]`, err);
    if (status === 413) {
      return res.status(413).json({ error: 'Request body is too large.', code: 'body_too_large' });
    }
    const body = {
      error: status >= 500 ? 'Something went wrong on the server. Please try again.' : (err.message || 'Server error'),
    };
    if (status < 500 && typeof err.code === 'string') body.code = err.code;
    res.status(status).json(body);
  });

  return app;
}

const app = createApp();

async function start() {
  await migrate();
  const PORT = process.env.PORT || 4000;
  return app.listen(PORT, '0.0.0.0', () => console.log(`API running on :${PORT}`));
}

if (require.main === module) {
  start().catch(err => {
    console.error('\n❌ DATABASE SE CONNECT NAHI HO PAYA:', err.message);
    if (!process.env.DATABASE_URL) console.error('👉 DATABASE_URL set nahi hai.');
    else if (err.code === 'ENOTFOUND') console.error('👉 DATABASE_URL galat hai. Render database page se "Internal Database URL" copy karke daalein.');
    else if (err.code === '28P01') console.error('👉 Database ka password galat hai.');
    process.exit(1);
  });
}

module.exports = { app, createApp, start };
