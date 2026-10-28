// SHOP LOGO → SQUARE TILE (auto-adjust, full-bleed)
//
// Shops ki report: "logo box me theek se set nahi hota — upar/neeche khaali
// jagah dikhti hai, aur logo ke aas-paas alag frame jaisa lagta hai". Wajah —
// thumbnail logo ko *fit* karta tha (poora dikhane ke liye), isliye square box
// me wide/portrait logo ke saath letterbox ki patti bach jati thi.
//
// Ab har logo ek hi tarah "set" hota hai — jaise app icon:
//   1. border ka median colour nikaal kar **background margin auto-trim**
//      (safed page / letterhead ka khali hissa tile me nahi aata),
//   2. square-ish logo → centre square **crop** (cover). Image box ko chaaron
//      taraf se bharti hai, koi patti nahi; app box ke corners round clip karta
//      hai, isliye image ke corners box jaisi shape me set hote hain.
//   3. wide/portrait logo (wordmark, banner) → **blurred backdrop**: poora logo
//      uske hi rang ke blur par centre me baithta hai (Instagram/Spotify style).
//      Isse na patti bachti hai, na text ke akshar kat te hain.
//   4. border ka rang saturated ho (brand ka indigo/green plate) to trim nahi
//      hota — plate hi content hai, aur wahi box bharta hai.
//
// App pehle hi har logo JPEG me convert karke bhejti hai (`document_photo`),
// isliye decode ke liye pure-JS JPEG decoder kaafi hai — Render par sharp/gyp
// ka jhanjhat nahi. PNG/WebP purane logo decode nahi ho paate: tab `null`
// lauta kar list me icon dikha dete hain.
const jpeg = require('jpeg-js');

/// Square tile side (44-56dp display ke liye 2-3x density par bhi sharp).
const THUMB_SIZE = 128;
/// PDF bill aur Profile card ke liye (58pt print ~ 300dpi ke aas paas).
const LOGO_SIZE = 512;
const THUMB_QUALITY = 82;
// Decode se pehle hi ruk jaate hain. App har logo 1200x1200 (1.4 MP) tak hi
// bhejti hai, isliye 8 MP se bada kuch aaye to use decode hi nahi karte —
// 8000x8000 solid JPEG 768 KB ke andar aa jata hai par decode 250 MB RAM leta hai.
const MAX_SOURCE_PIXELS = 8 * 1000 * 1000;
const MAX_SOURCE_BYTES = 768 * 1024; // = validation.SHOP_LOGO_MAX_BYTES
const MAX_THUMB_CHARS = 33 * 1024;
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
function resample(src, sw, box, dw, dh) {
  const out = Buffer.alloc(dw * dh * 4);
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
          // Source ka apna alpha (PNG upload) — safed par flatten.
          const px = src[i + 3] / 255;
          r += src[i] * px;
          g += src[i + 1] * px;
          b += src[i + 2] * px;
          a += px;
          n++;
        }
      }
      const o = (y * dw + x) * 4;
      // Opaque output (JPEG tile): transparent source safed par flatten hota hai.
      out[o] = Math.min(255, Math.round(r / n + 255 * (1 - a / n)));
      out[o + 1] = Math.min(255, Math.round(g / n + 255 * (1 - a / n)));
      out[o + 2] = Math.min(255, Math.round(b / n + 255 * (1 - a / n)));
      out[o + 3] = 255;
    }
  }
  return out;
}

/// Box blur (separable) — backdrop ke liye. 128/512px tile par sasta hai.
function blurRgba(data, size, radius) {
  if (radius < 1) return data;
  const tmp = Buffer.alloc(data.length);
  const out = Buffer.alloc(data.length);
  const pass = (src, dst, horizontal) => {
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        let r = 0, g = 0, b = 0, n = 0;
        for (let k = -radius; k <= radius; k++) {
          const sx = horizontal ? Math.min(size - 1, Math.max(0, x + k)) : x;
          const sy = horizontal ? y : Math.min(size - 1, Math.max(0, y + k));
          const i = (sy * size + sx) * 4;
          r += src[i]; g += src[i + 1]; b += src[i + 2]; n++;
        }
        const o = (y * size + x) * 4;
        dst[o] = Math.round(r / n); dst[o + 1] = Math.round(g / n); dst[o + 2] = Math.round(b / n); dst[o + 3] = 255;
      }
    }
  };
  pass(data, tmp, true);
  pass(tmp, out, false);
  return out;
}

/// Decoded RGBA → square **full-bleed** tile.
///
///   * square-ish logo (aspect ~1) → centre square **crop** (cover): image box ko
///     poora bharta hai, koi patti nahi, corners app clip karta hai.
///   * wide/portrait logo (wordmark, banner) → **blurred backdrop**: poora logo
///     uske hi rang ka blur ban kar box bharta hai aur logo upar centre me
///     poora dikhta hai (Instagram/Spotify jaisa). Isse na patti bachti hai,
///     na wordmark ke akshar kat te hain.
function squareTile(decoded, { size = THUMB_SIZE } = {}) {
  const sw = decoded.width | 0, sh = decoded.height | 0;
  const src = decoded.data;
  const bg = borderColor(src, sw, sh);
  const neutral = isNeutral(bg);
  const box = neutral
    ? trimBox(src, sw, sh, bg)
    : { x: 0, y: 0, width: sw, height: sh, trimmed: false };

  // Cover crop: chhoti side ke barabar ka square, centre me.
  const side = Math.max(1, Math.min(box.width, box.height));
  const cover = {
    x: box.x + Math.floor((box.width - side) / 2),
    y: box.y + Math.floor((box.height - side) / 2),
    width: side,
    height: side,
  };

  const aspect = box.width / box.height;
  const squareish = aspect >= 0.82 && aspect <= 1.22;

  if (squareish) {
    return {
      data: resample(src, sw, cover, size, size),
      width: size, height: size, trimmed: box.trimmed, border: bg, neutral, backdrop: false,
    };
  }

  // Backdrop: cover crop ko blur + halka dim (upar wala logo padhne layak rahe).
  const base = blurRgba(resample(src, sw, cover, size, size), size, Math.max(2, Math.round(size / 9)));
  for (let i = 0; i < base.length; i += 4) {
    base[i] = Math.round(base[i] * 0.82);
    base[i + 1] = Math.round(base[i + 1] * 0.82);
    base[i + 2] = Math.round(base[i + 2] * 0.82);
  }

  // Poora content upar, box ka ~84% — koi akshar nahi katta.
  const avail = Math.max(1, Math.round(size * 0.84));
  const scale = Math.min(avail / box.width, avail / box.height);
  const fw = Math.max(1, Math.round(box.width * scale));
  const fh = Math.max(1, Math.round(box.height * scale));
  const fitted = resample(src, sw, box, fw, fh);
  const ox = Math.floor((size - fw) / 2), oy = Math.floor((size - fh) / 2);
  for (let y = 0; y < fh; y++) {
    const to = ((oy + y) * size + ox) * 4;
    fitted.copy(base, to, (y * fw) * 4, (y * fw + fw) * 4);
  }
  return { data: base, width: size, height: size, trimmed: box.trimmed, border: bg, neutral, backdrop: true };
}

/// Ek decoded image → square full-bleed tile (requested size), `null` on failure.
function encodeTile(decoded, { size, quality, maxChars }) {
  let tile;
  try { tile = squareTile(decoded, { size }); } catch { return null; }

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

/// Shop logo (JPEG data URL) → chhota square **full-bleed** JPEG (`128`, list
/// ke liye), ya `null` jab banana possible na ho (PNG/WebP, corrupt, bahut bada).
function shopThumb(dataUrl, { size = THUMB_SIZE, quality = THUMB_QUALITY } = {}) {
  const decoded = decode(dataUrl);
  if (!decoded) return null;
  return encodeTile(decoded, { size, quality, maxChars: MAX_THUMB_CHARS });
}

/// Upload par **ek hi baar** auto-adjust: poora logo 512px full-bleed square
/// tile ban jata hai (margin trim + centre crop), aur usi decode se 128px list
/// thumbnail bhi. Isliye PDF bill, Profile card, Home top bar aur Super Admin
/// list — sab me logo ek jaisa, box ko poora bhara hua dikhta hai.
/// `null` = image auto-adjust nahi ho sakti (PNG/WebP/corrupt) — caller original
/// rakh kar sirf thumbnail chhod de.
function shopLogoTiles(dataUrl, { force = false } = {}) {
  const decoded = decode(dataUrl);
  if (!decoded) return null;
  // Pehle se naya (cover) tile hai — dobara encode karke quality kharab mat karo,
  // sirf list ka thumbnail bana lo. `force` purane letterbox wale tiles ke liye
  // (migration), jahan crop dobara karna zaroori hai.
  if (!force && decoded.width === LOGO_SIZE && decoded.height === LOGO_SIZE) {
    const thumb = encodeTile(decoded, { size: THUMB_SIZE, quality: THUMB_QUALITY, maxChars: MAX_THUMB_CHARS });
    return thumb ? { logo: dataUrl, thumb } : null;
  }
  // 512px tile detail wale logo par bhi ~150 KB; cap 600 KB chars (validation
  // ki 768 KB binary limit ke andar rehne ke liye).
  const logo = encodeTile(decoded, { size: LOGO_SIZE, quality: 86, maxChars: 600 * 1024 });
  if (!logo) return null;
  const thumb = encodeTile(decoded, { size: THUMB_SIZE, quality: THUMB_QUALITY, maxChars: MAX_THUMB_CHARS });
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
  shopThumb, shopLogoTiles, squareTile, trimBox, borderColor, resample, jpegBytes, jpegSize, isNeutral, blurRgba,
  THUMB_SIZE, LOGO_SIZE, MAX_THUMB_CHARS,
};
