// SHOP LOGO THUMBNAILS
//
// PDF bill ka logo poora (base64) `shops.logo_data` me rehta hai — 100-700 KB
// tak. Super Admin ki shop list me wo bhejna possible nahi (20 shops = 10 MB+),
// isliye upload ke waqt hi ek chhota thumbnail bana kar `logo_thumb` me rakhte
// hain (96px, ~2-4 KB) aur list sirf wahi bhejti hai.
//
// App pehle hi har logo ko JPEG me convert karke bhejti hai (`document_photo`),
// isliye decode ke liye ek chhota pure-JS JPEG decoder kaafi hai — koi native
// build nahi (Render par sharp/gyp install ka jhanjhat nahi).
// PNG/WebP purane logo decode nahi ho paate: tab `null` lauta kar list me shop
// ka icon dikha dete hain (kuch toota nahi).
const jpeg = require('jpeg-js');

// List ke 44x44 box ke liye 96px kaafi hai (2x density par bhi sharp).
const THUMB_MAX_SIDE = 96;
const THUMB_QUALITY = 72;
// Decode se pehle hi ruk jaate hain. App har logo 1200x1200 (1.4 MP) tak hi
// bhejti hai, isliye 8 MP se bada kuch aaye to use decode hi nahi karte —
// 8000x8000 solid JPEG 768 KB ke andar aa jata hai par decode 250 MB RAM leta hai.
const MAX_SOURCE_PIXELS = 8 * 1000 * 1000;
const MAX_SOURCE_BYTES = 768 * 1024; // = validation.SHOP_LOGO_MAX_BYTES
// Validation ki imageDataUrl limit ke andar rehna zaroori hai.
const MAX_THUMB_CHARS = 33 * 1024;

/// Base64 data URL se bytes (schema check ke saath). Sirf JPEG — baaki null.
function jpegBytes(dataUrl) {
  if (typeof dataUrl !== 'string' || !dataUrl.startsWith('data:image/jpeg;base64,'))
    return null;
  const encoded = dataUrl.slice('data:image/jpeg;base64,'.length);
  if (!encoded) return null;
  let buf;
  try { buf = Buffer.from(encoded, 'base64'); } catch { return null; }
  if (!buf.length || buf.length > MAX_SOURCE_BYTES) return null;
  return buf;
}

/// Box filter (har output pixel = uske area ke input pixels ka average). Logo jaise
/// flat graphics par nearest-neighbour se kaafi saaf aata hai aur sasta hai.
/// Transparent pixels safed par composite hote hain kyunki JPEG me alpha nahi hota.
function downscale(src, sw, sh, dw, dh) {
  const out = Buffer.alloc(dw * dh * 4);
  for (let y = 0; y < dh; y++) {
    const y0 = Math.floor((y * sh) / dh);
    const y1 = Math.min(sh, Math.max(y0 + 1, Math.floor(((y + 1) * sh) / dh)));
    for (let x = 0; x < dw; x++) {
      const x0 = Math.floor((x * sw) / dw);
      const x1 = Math.min(sw, Math.max(x0 + 1, Math.floor(((x + 1) * sw) / dw)));
      let r = 0, g = 0, b = 0, n = 0;
      for (let sy = y0; sy < y1; sy++) {
        for (let sx = x0; sx < x1; sx++) {
          const i = (sy * sw + sx) * 4;
          const alpha = src[i + 3] / 255;
          // safed background par blend
          r += src[i] * alpha + 255 * (1 - alpha);
          g += src[i + 1] * alpha + 255 * (1 - alpha);
          b += src[i + 2] * alpha + 255 * (1 - alpha);
          n++;
        }
      }
      const o = (y * dw + x) * 4;
      out[o] = Math.round(r / n);
      out[o + 1] = Math.round(g / n);
      out[o + 2] = Math.round(b / n);
      out[o + 3] = 255; // JPEG me alpha nahi hota; sab safed par flatten ho chuka
    }
  }
  return out;
}

/// Shop logo (JPEG data URL) → chhota JPEG data URL, ya `null` jab thumbnail
/// banana possible na ho (PNG/WebP, corrupt file, bahut bada).
function shopThumb(dataUrl, { maxSide = THUMB_MAX_SIDE, quality = THUMB_QUALITY } = {}) {
  const buf = jpegBytes(dataUrl);
  if (!buf) return null;
  let decoded;
  try {
    decoded = jpeg.decode(buf, { useTArray: true, formatAsRGBA: true, maxMemoryUsageInMB: 128 });
  } catch {
    return null;
  }
  const sw = decoded.width | 0, sh = decoded.height | 0;
  if (!sw || !sh || sw * sh > MAX_SOURCE_PIXELS) return null;
  // Pehle se chhota hai to dobara encode karke quality kharab karne ka fayda nahi.
  const scale = Math.min(1, maxSide / Math.max(sw, sh));
  const dw = Math.max(1, Math.round(sw * scale));
  const dh = Math.max(1, Math.round(sh * scale));
  const rgba = scale === 1 ? Buffer.from(decoded.data) : downscale(decoded.data, sw, sh, dw, dh);

  // Chhota rakhne ke liye quality step-down (bade/complex logo par bhi limit ke andar).
  for (const q of [quality, 55, 40]) {
    let encoded;
    try {
      encoded = jpeg.encode({ data: rgba, width: dw, height: dh }, q).data;
    } catch {
      return null;
    }
    const url = `data:image/jpeg;base64,${Buffer.from(encoded).toString('base64')}`;
    if (url.length <= MAX_THUMB_CHARS) return url;
  }
  return null;
}

module.exports = { shopThumb, jpegBytes, downscale, THUMB_MAX_SIDE, MAX_THUMB_CHARS };
