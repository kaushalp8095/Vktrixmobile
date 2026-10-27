// Logo thumbnail ka "safed box" fix:
//   * safed (neutral) page par bane logo ka margin **transparent PNG** ban jata hai —
//     dark theme me logo ke chaaron taraf safed plate nahi dikhti
//   * full-bleed brand plate (indigo/green background) ke liye plate hi tile ka
//     background banta hai — letterbox ki patti gayab
//   * PDF/print ke liye stored 512px logo JPEG hi rehta hai (alpha support nahi)
const { test } = require('node:test');
const assert = require('node:assert/strict');
const zlib = require('node:zlib');
const jpeg = require('jpeg-js');

const thumb = require('../src/thumb');

/// PNG (RGBA, filter 0-4) → { width, height, data }.
function decodePng(url) {
  const buf = Buffer.from(String(url).split(',')[1], 'base64');
  assert.equal(buf.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', 'PNG signature');
  let off = 8, width = 0, height = 0;
  const idat = [];
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.subarray(off + 4, off + 8).toString('ascii');
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') { width = data.readUInt32BE(0); height = data.readUInt32BE(4); }
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    off += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * 4;
  const out = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    const f = raw[y * (stride + 1)];
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= 4 ? out[y * stride + i - 4] : 0;
      const b = y > 0 ? out[(y - 1) * stride + i] : 0;
      const c = i >= 4 && y > 0 ? out[(y - 1) * stride + i - 4] : 0;
      let v = src[i];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      } else assert.equal(f, 0, 'unknown filter');
      out[y * stride + i] = v & 0xff;
    }
  }
  return { width, height, data: out };
}

const px = (img, x, y) => {
  const i = (y * img.width + x) * 4;
  return [img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3]];
};

function encodeJpeg(width, height, paint) {
  const data = Buffer.alloc(width * height * 4, 255);
  paint(data, width);
  return 'data:image/jpeg;base64,' + jpeg.encode({ data, width, height }, 95).data.toString('base64');
}

const fill = (d, w, x0, y0, x1, y1, [r, g, b]) => {
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    const i = (y * w + x) * 4;
    d[i] = r; d[i + 1] = g; d[i + 2] = b; d[i + 3] = 255;
  }
};

// Safed page + beech me brand ka block (asli dukaan wale logo jaisa).
const PAGE_LOGO = encodeJpeg(600, 400, (d, w) => fill(d, w, 170, 120, 430, 300, [63, 81, 181]));
// Full-bleed brand plate (photo ke kinare tak rang) — plate hi logo hai.
const PLATE_LOGO = encodeJpeg(400, 400, (d, w) => {
  fill(d, w, 0, 0, 400, 400, [20, 40, 160]);
  fill(d, w, 180, 110, 220, 290, [255, 255, 255]);
});

test('safed page ke logo ka margin transparent — white box nahi', () => {
  const url = thumb.shopThumb(PAGE_LOGO);
  assert.match(url, /^data:image\/png;base64,/, 'transparent thumb PNG hota hai');
  const img = decodePng(url);
  assert.deepEqual({ width: img.width, height: img.height }, { width: 128, height: 128 });

  // Chaaron kone poori tarah transparent.
  for (const [x, y] of [[0, 0], [127, 0], [0, 127], [127, 127]]) {
    assert.equal(px(img, x, y)[3], 0, `corner ${x},${y} transparent`);
  }
  // Logo wala hissa opaque hai (gayab nahi hua).
  const centre = px(img, 64, 64);
  assert.equal(centre[3], 255, 'logo opaque');
  assert.ok(centre[2] > 120 && centre[2] > centre[0], 'logo ka rang wahi (indigo)');

  // Safed margin tile me kahin bacha nahi (alpha 0 wala area hi hai).
  let opaqueWhite = 0;
  for (let y = 0; y < 128; y++) for (let x = 0; x < 128; x++) {
    const [r, g, b, a] = px(img, x, y);
    if (a > 0 && r > 240 && g > 240 && b > 240) opaqueWhite++;
  }
  assert.equal(opaqueWhite, 0, 'safed plate nahi bachti');

  // 128px ke liye list-friendly size.
  assert.ok(url.length < 48 * 1024, `thumb too big: ${url.length}`);
});

test('full-bleed brand plate ka tile poora bhara (koi patti nahi)', () => {
  const url = thumb.shopThumb(PLATE_LOGO);
  assert.match(url, /^data:image\/jpeg;base64,/, 'plate wale logo ka tile opaque rehta hai');
  const img = jpeg.decode(Buffer.from(url.split(',')[1], 'base64'), { useTArray: true });
  assert.deepEqual({ width: img.width, height: img.height }, { width: 128, height: 128 });
  // Edge par bhi brand ka rang — safed kinara nahi.
  for (const [x, y] of [[1, 1], [126, 1], [1, 126], [126, 126]]) {
    const [r, g, b] = px(img, x, y);
    assert.ok(b > r && b > 100 && r < 90, `edge brand colour: ${r},${g},${b}`);
  }
});

test('stored logo PDF ke liye opaque JPEG hi rehta hai', () => {
  const tiles = thumb.shopLogoTiles(PAGE_LOGO);
  assert.match(tiles.logo, /^data:image\/jpeg;base64,/);
  assert.match(tiles.thumb, /^data:image\/png;base64,/);
  const logo = jpeg.decode(Buffer.from(tiles.logo.split(',')[1], 'base64'), { useTArray: true });
  assert.deepEqual({ width: logo.width, height: logo.height }, { width: 512, height: 512 });
  const i = (256 * logo.width + 256) * 4;
  assert.equal(logo.data[i + 3], 255, 'JPEG ka alpha 255 hi hota hai');
});

test('purana JPEG thumbnail bhi naye transparent roop me aata hai (idempotent)', () => {
  const first = thumb.shopThumb(PAGE_LOGO);
  const second = thumb.shopThumb(PAGE_LOGO);
  assert.equal(first, second, 'same input → same thumb (backfill dobara nahi chalega)');
});
