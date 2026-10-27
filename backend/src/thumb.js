// SHOP LOGO → SQUARE TILE (auto-adjust)
//
// Problem jo shops ne report kiya: "logo upload hota hai par theek se set nahi
// hota". Wajah do thi —
//   1. thumbnail source ka aspect ratio le leta tha (2:1 logo → 96x48), aur
//      app 44x44 box me `contain` karti thi, isliye logo chhota floating dikhta tha;
//   2. logon ke logo me aas-paas safed/blank margin hota hai (screenshot, photo,
//      letterhead scan), jo tile me aur zyada khaali jagah bana deta tha.
//
// Ab har logo ek hi tarah "set" hota hai (jaise app icon):
//   1. border ka median colour nikaal kar **background margin auto-trim**,
//   2. bacha hua logo **square canvas** par bara karke centre me rakha jata hai
//      (chhota 4% padding),
//   3. list ka thumbnail **transparent PNG** hota hai — margin cut, isliye dark
//      theme me logo ke aas-paas safed plate nahi dikhti (JPEG me alpha nahi
//      hota, isliye pehle white box rehta tha),
//   4. PDF/print ke liye stored 512px logo JPEG hi rehta hai (safed canvas) —
//      wahan transparency ka matlab hi nahi.
//   5. Agar border ka rang neutral nahi (brand ka full-bleed plate: indigo,
//      green…), to tile ka background wahi plate colour ho jata hai — letterbox
//      ki patti gayab, box poora bhara dikhta hai.
//
// App pehle hi har logo JPEG me convert karke bhejti hai (`document_photo`),
// isliye decode ke liye pure-JS JPEG decoder kaafi hai — Render par sharp/gyp
// ka jhanjhat nahi. PNG/WebP purane logo decode nahi ho paate: tab `null`
// lauta kar list me icon dikha dete hain.
const jpeg = require('jpeg-js');
const { encodePng } = require('./png');

/// Square tile side (44-56dp display ke liye 2-3x density par bhi sharp).
const THUMB_SIZE = 128;
/// PDF bill aur Profile card ke liye (58pt print ~ 300dpi ke aas paas).
const LOGO_SIZE = 512;
/// Logo aur tile ke kinare ke beech ki jagah (tile ka ~4%).
const THUMB_PAD = 5;
const THUMB_QUALITY = 82;
// Decode se pehle hi ruk jaate hain. App har logo 1200x1200 (1.4 MP) tak hi
// bhejti hai, isliye 8 MP se bada kuch aaye to use decode hi nahi karte —
// 8000x8000 solid JPEG 768 KB ke andar aa jata hai par decode 250 MB RAM leta hai.
const MAX_SOURCE_PIXELS = 8 * 1000 * 1000;
const MAX_SOURCE_BYTES = 768 * 1024; // = validation.SHOP_LOGO_MAX_BYTES
const MAX_THUMB_CHARS = 33 * 1024;
const MAX_PNG_THUMB_CHARS = 48 * 1024; // transparent thumb (PNG) ka budget
/// Background maanne ke liye per-channel tolerance (JPEG compression se bachne layak).
const BG_TOLERANCE = 24;

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

/// JPEG ka sirf header padh kar dimensions (SOF marker). Base64 decode + poora
/// pixel decode kiye bina "ye logo pehle se normalized hai kya" pata chal jata hai —
/// migration me har shop ka 700 KB image decode karna mehnga padta.
function jpegSize(buf) {
  if (!buf || buf.length < 4 || buf[0] !== 0xFF || buf[1] !== 0xD8) return null;
  let i = 2;
  while (i + 9 < buf.length) {
    if (buf[i] !== 0xFF) { i++; continue; }
    const marker = buf[i + 1];
    if (marker === 0xD8 || marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) { i += 2; continue; }
    const length = buf.readUInt16BE(i + 2);
    if (length < 2) return null;
    // SOF0..SOF15 (C4/C8/CC chhod kar) me height/width hote hain.
    if (marker >= 0xC0 && marker <= 0xCF && marker !== 0xC4 && marker !== 0xC8 && marker !== 0xCC) {
      return { height: buf.readUInt16BE(i + 5), width: buf.readUInt16BE(i + 7) };
    }
    i += 2 + length;
  }
  return null;
}

/// Kinare ke pixels ka median — JPEG noise aur ek-do safed pixel se nahi hilti.
function borderColor(src, w, h) {
  const rs = [], gs = [], bs = [];
  const stepX = Math.max(1, Math.floor(w / 64));
  const stepY = Math.max(1, Math.floor(h / 64));
  const sample = (x, y) => {
    const i = (y * w + x) * 4;
    const a = src[i + 3] / 255;
    // transparent pixels safed par composite hote hain (JPEG me alpha nahi)
    rs.push(src[i] * a + 255 * (1 - a));
    gs.push(src[i + 1] * a + 255 * (1 - a));
    bs.push(src[i + 2] * a + 255 * (1 - a));
  };
  for (let x = 0; x < w; x += stepX) { sample(x, 0); sample(x, h - 1); }
  for (let y = 0; y < h; y += stepY) { sample(0, y); sample(w - 1, y); }
  const median = list => {
    list.sort((p, q) => p - q);
    return list[Math.floor(list.length / 2)] || 0;
  };
  return { r: median(rs), g: median(gs), b: median(bs) };
}

/// Border ka colour "page/margin" hai ya logo ka hi plate?
///   * neutral (safed, kaala, gray)  → margin hai: trim + transparent cut.
///   * saturated (brand indigo/green) → design ka hissa hai (full-bleed plate):
///     trim nahi, aur tile ka background wahi colour — plate chup-chaap tile bhar deta hai.
function isNeutral(bg) {
  const max = Math.max(bg.r, bg.g, bg.b), min = Math.min(bg.r, bg.g, bg.b);
  return max - min <= 32;
}

const isBackground = (src, i, bg) =>
  Math.abs(src[i] - bg.r) <= BG_TOLERANCE
  && Math.abs(src[i + 1] - bg.g) <= BG_TOLERANCE
  && Math.abs(src[i + 2] - bg.b) <= BG_TOLERANCE;

/// Pura row/column background hai? (2% pixels alag hon to bhi chalta hai — JPEG
/// noise aur bilkul kinare par pada ek-do anti-aliased pixel isse rukta nahi.)
function lineIsBackground(src, w, h, line, horizontal, bg) {
  const length = horizontal ? w : h;
  const step = Math.max(1, Math.floor(length / 80));
  let checked = 0, different = 0;
  for (let i = 0; i < length; i += step) {
    const x = horizontal ? i : line;
    const y = horizontal ? line : i;
    checked++;
    if (!isBackground(src, (y * w + x) * 4, bg)) different++;
  }
  return different <= Math.max(1, Math.floor(checked * 0.02));
}

/// Background margin ka box. Kuch na mile to pura image.
function trimBox(src, w, h, bg) {
  let top = 0, bottom = h - 1, left = 0, right = w - 1;
  while (top < bottom && lineIsBackground(src, w, h, top, true, bg)) top++;
  while (bottom > top && lineIsBackground(src, w, h, bottom, true, bg)) bottom--;
  while (left < right && lineIsBackground(src, w, h, left, false, bg)) left++;
  while (right > left && lineIsBackground(src, w, h, right, false, bg)) right--;
  const tw = right - left + 1, th = bottom - top + 1;
  // Bahut chhota "content" mile (ek dot / noise) to trim ko ignore karte hain —
  // warna wo dot poore tile par blur ho kar kharab dikhega.
  if (tw < w * 0.15 || th < h * 0.15) return { x: 0, y: 0, width: w, height: h, trimmed: false };
  const trimmed = tw < w || th < h;
  return { x: left, y: top, width: tw, height: th, trimmed };
}

/// Box filter (area average). Downscale par har output pixel apne area ka
/// average leta hai; small upscale par bhi same code (1-2 source pixels) chalta hai.
function resample(src, sw, box, dw, dh, bg = null, feather = BG_TOLERANCE) {
  const out = Buffer.alloc(dw * dh * 4);
  const cut = bg != null;
  for (let y = 0; y < dh; y++) {
    const y0 = box.y + Math.floor((y * box.height) / dh);
    const y1 = Math.max(y0 + 1, box.y + Math.floor(((y + 1) * box.height) / dh));
    for (let x = 0; x < dw; x++) {
      const x0 = box.x + Math.floor((x * box.width) / dw);
      const x1 = Math.max(x0 + 1, box.x + Math.floor(((x + 1) * box.width) / dw));
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      for (let sy = y0; sy < y1; sy++) {
        for (let sx = x0; sx < x1; sx++) {
          const i = (sy * sw + sx) * 4;
          // Source ka apna alpha (PNG) aur humara "background" mask — dono.
          const srcA = src[i + 3] / 255;
          const maskA = cut ? alphaFor([src[i], src[i + 1], src[i + 2]], bg, feather) / 255 : 1;
          const px = srcA * maskA;
          // Premultiplied average: edge par kaale/safed halo ke bina.
          r += src[i] * px;
          g += src[i + 1] * px;
          b += src[i + 2] * px;
          a += px;
          n++;
        }
      }
      const o = (y * dw + x) * 4;
      if (cut) {
        out[o] = a > 0 ? Math.min(255, Math.round(r / a)) : 0;
        out[o + 1] = a > 0 ? Math.min(255, Math.round(g / a)) : 0;
        out[o + 2] = a > 0 ? Math.min(255, Math.round(b / a)) : 0;
        out[o + 3] = Math.round((a / n) * 255);
      } else {
        // Opaque: safed par flatten (JPEG me alpha nahi hota).
        out[o] = Math.round(r / n + 255 * (1 - a / n));
        out[o + 1] = Math.round(g / n + 255 * (1 - a / n));
        out[o + 2] = Math.round(b / n + 255 * (1 - a / n));
        out[o + 3] = 255;
      }
    }
  }
  return out;
}

/// Decoded RGBA → square tile jisme logo centre me hota hai.
///
/// `transparent: true` par background ke pixels ka alpha 0 ho jata hai (PNG
/// thumbnail — app ke glass tile par white box nahi dikhta). Alpha edge par
/// soft rehta hai kyunki resample premultiplied hota hai. `transparent: false`
/// par safed canvas (JPEG/PDF ke liye; alpha support nahi hota).
function squareTile(decoded, { size = THUMB_SIZE, pad = THUMB_PAD, transparent = false, feather = BG_TOLERANCE } = {}) {
  const sw = decoded.width | 0, sh = decoded.height | 0;
  const src = decoded.data;
  const bg = borderColor(src, sw, sh);
  const neutral = isNeutral(bg);
  const box = neutral ? trimBox(src, sw, sh, bg) : { x: 0, y: 0, width: sw, height: sh, trimmed: false };
  // Trim hi nahi hua = image ke kinare hi content hain (background nahi mila).
  // Aise logo ko transparent karna galat hoga (white-on-white logo gayab ho jata).
  const cut = transparent && neutral && box.trimmed;
  const avail = Math.max(1, size - pad * 2);
  const scale = Math.min(avail / box.width, avail / box.height);
  const dw = Math.max(1, Math.round(box.width * scale));
  const dh = Math.max(1, Math.round(box.height * scale));
  const logo = resample(src, sw, box, dw, dh, cut ? bg : null, feather);

  const canvas = Buffer.alloc(size * size * 4); // RGBA, sab 0 (transparent)
  if (!cut) {
    // Opaque canvas. Background = border ka colour: safed page par safed,
    // brand plate par wahi brand colour (letterbox ki patti gayab).
    const fill = neutral ? { r: 255, g: 255, b: 255 } : bg;
    for (let i = 0; i < canvas.length; i += 4) {
      canvas[i] = fill.r; canvas[i + 1] = fill.g; canvas[i + 2] = fill.b; canvas[i + 3] = 255;
    }
  }
  const ox = Math.floor((size - dw) / 2), oy = Math.floor((size - dh) / 2);
  for (let y = 0; y < dh; y++) {
    const to = ((oy + y) * size + ox) * 4;
    logo.copy(canvas, to, (y * dw) * 4, (y * dw + dw) * 4);
  }
  return { data: canvas, width: size, height: size, trimmed: box.trimmed, transparent: cut, border: bg, neutral };
}

/// Background se distance → alpha. Safed margin ke aas-paas ek patli soft edge
/// (anti-alias) rehti hai, isliye PNG edge par jaggies nahi dikhte.
function alphaFor(px, bg, feather) {
  if (!bg) return 255;
  const d = Math.max(Math.abs(px[0] - bg.r), Math.abs(px[1] - bg.g), Math.abs(px[2] - bg.b));
  if (d <= feather * 0.5) return 0;
  if (d >= feather * 1.5) return 255;
  return Math.round(((d - feather * 0.5) / feather) * 255);
}

/// Ek decoded image → square tile (requested size), `null` on failure.
function encodeTile(decoded, { size, pad, quality, maxChars, transparent = false }) {
  let tile;
  try { tile = squareTile(decoded, { size, pad, transparent }); } catch { return null; }

  // Transparent tile sirf PNG me ho sakta hai (JPEG me alpha nahi hota).
  // 128px ke liye PNG ~5-25 KB rehta hai — budget se bada ho to JPEG (safed)
  // par gir jaate hain, taaki list ka response bhaari na ho.
  if (tile.transparent) {
    try {
      const png = encodePng(tile.data, tile.width, tile.height);
      const url = `data:image/png;base64,${png.toString('base64')}`;
      // PNG JPEG se bada hota hai; transparent rakhna zaroori hai (safed box
      // nahi), isliye iske liye alag, thoda udaar budget.
      if (url.length <= Math.max(maxChars, MAX_PNG_THUMB_CHARS)) return url;
    } catch { /* fall through to JPEG */ }
  }

  // Chhota rakhne ke liye quality step-down (detail wale logo par bhi limit ke andar).
  for (const q of [quality, 70, 55, 45]) {
    let encoded;
    try {
      encoded = jpeg.encode({ data: tile.data, width: tile.width, height: tile.height }, q).data;
    } catch {
      return null;
    }
    const url = `data:image/jpeg;base64,${Buffer.from(encoded).toString('base64')}`;
    if (url.length <= maxChars) return url;
  }
  return null;
}

/// Shop logo (JPEG data URL) → chhota square **transparent PNG** (`128`, list
/// ke liye), ya `null` jab banana possible na ho (PNG/WebP, corrupt, bahut bada).
function shopThumb(dataUrl, { size = THUMB_SIZE, pad = THUMB_PAD, quality = THUMB_QUALITY } = {}) {
  const decoded = decode(dataUrl);
  if (!decoded) return null;
  // List/Profile/Home ke liye **transparent** PNG: margin cut, isliye app ke
  // glass tile par white box nahi dikhta. Thumb fail kare to JPEG (safed).
  return encodeTile(decoded, { size, pad, quality, maxChars: MAX_THUMB_CHARS, transparent: true });
}

/// Upload par **ek hi baar** auto-adjust: poora logo 512px square tile ban jata
/// hai (margin trim + centre), aur usi decode se 128px list thumbnail bhi.
/// Isse PDF bill, Profile card aur Super Admin list — teeno me logo ek jaisa
/// "set" dikhta hai, chahe shop ne kisi bhi shape ka image chuna ho.
/// `null` = image auto-adjust nahi ho sakti (PNG/WebP/corrupt) — caller original
/// rakh kar sirf thumbnail chhod de.
function shopLogoTiles(dataUrl) {
  const decoded = decode(dataUrl);
  if (!decoded) return null;
  // Pehle se normalized (512x512) — dobara encode karke quality kharab mat karo,
  // sirf list ka thumbnail bana lo. (Idempotent, warna har save par recompress.)
  if (decoded.width === LOGO_SIZE && decoded.height === LOGO_SIZE) {
    const thumb = encodeTile(decoded, { size: THUMB_SIZE, pad: THUMB_PAD, quality: THUMB_QUALITY, maxChars: MAX_THUMB_CHARS, transparent: true });
    return thumb ? { logo: dataUrl, thumb } : null;
  }
  // 512px tile detail wale logo par bhi ~150 KB; cap 600 KB chars (validation
  // ki 768 KB binary limit ke andar rehne ke liye).
  const logo = encodeTile(decoded, { size: LOGO_SIZE, pad: 10, quality: 86, maxChars: 600 * 1024 });
  if (!logo) return null;
  const thumb = encodeTile(decoded, { size: THUMB_SIZE, pad: THUMB_PAD, quality: THUMB_QUALITY, maxChars: MAX_THUMB_CHARS, transparent: true });
  return { logo, thumb };
}

function decode(dataUrl) {
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
  return decoded;
}

module.exports = {
  shopThumb, shopLogoTiles, squareTile, trimBox, borderColor, resample, jpegBytes, jpegSize, alphaFor, isNeutral,
  THUMB_SIZE, THUMB_PAD, LOGO_SIZE, MAX_THUMB_CHARS,
};
