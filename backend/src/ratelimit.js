// RATE LIMITING / BRUTE-FORCE PROTECTION
//
// Bina iske `/api/auth/login` par ek script raat bhar passwords try kar sakti thi
// (shop passwords minimum 8 characters ke hote hain, aur username guess karna
// aasan hai). Yahan ek chhota, dependency-free fixed-window counter hai:
//   * login: per-username attempts + per-IP cap (dono)
//   * change-password: per-user
//   * poora API: per-IP cap (scraping / memory DoS)
//
// Fixed window jaan-boojh kar: memory O(keys), koi background timer nahi (process
// sleep jaaye to bhi kuch leak nahi hota), aur window ke andar hi reset hota hai.
// Multi-instance deployment me har instance ka apna counter hoga — is app me ek hi
// instance chalta hai; zyada instances hone par Redis par shift karna hoga
// (README/security doc me likha hai).
const stores = new Map();

const nowMs = () => Date.now();

function store(name) {
  let s = stores.get(name);
  if (!s) { s = new Map(); stores.set(name, s); }
  return s;
}

// Purani entries hata dete hain warna Map hamesha badhta rahega.
function sweep(entries, t) {
  for (const [key, entry] of entries) if (entry.resetAt <= t) entries.delete(key);
}

/// Ek attempt ginta hai. `limited` true hone par caller ko 429 dena chahiye.
function hit({ name, key, windowMs, max, at = nowMs() }) {
  const entries = store(name);
  // Bade Map par har call sweep karna O(n) ho jata; 4096 ke baad hi saaf karte hain.
  if (entries.size > 4096) sweep(entries, at);
  const k = String(key == null ? 'unknown' : key);
  let entry = entries.get(k);
  if (!entry || entry.resetAt <= at) {
    entry = { count: 0, resetAt: at + windowMs };
    entries.set(k, entry);
  }
  entry.count += 1;
  const retryAfter = Math.max(1, Math.ceil((entry.resetAt - at) / 1000));
  return { limited: entry.count > max, count: entry.count, retryAfter };
}

/// Successful login ke baad us username ka counter saaf (galtiyan bhool jao).
function reset({ name, key }) {
  store(name).delete(String(key == null ? 'unknown' : key));
}

function resetAll() { stores.clear(); }

const DEFAULT_MESSAGE = 'Bahut zyada requests aa rahi hain. Thodi der baad try karein.';
const DEFAULT_CODE = 'rate_limited';

/// Express middleware. `key` default IP hai; per-user limits ke liye `req.user.id`
/// bhejein. Har response par standard `RateLimit-Limit` header jaata hai.
function createLimiter({
  name, windowMs = 60 * 1000, max = 300,
  key = req => req.ip,
  skip = () => false,
  message = DEFAULT_MESSAGE,
  code = DEFAULT_CODE,
}) {
  const label = name || `limiter-${windowMs}-${max}`;
  return (req, res, next) => {
    if (skip(req)) return next();
    const result = hit({ name: label, key: key(req), windowMs, max });
    res.setHeader('RateLimit-Limit', String(max));
    if (!result.limited) return next();
    res.setHeader('Retry-After', String(result.retryAfter));
    res.setHeader('RateLimit-Remaining', '0');
    res.status(429).json({ error: message, code, retry_after_seconds: result.retryAfter });
  };
}

module.exports = { createLimiter, hit, reset, resetAll, _stores: stores };
