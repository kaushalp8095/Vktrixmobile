// Logo tile: box me poora set (full-bleed).
//
// Shops ki report: "logo box me upar-neeche khaali jagah dikhti hai, aur logo ke
// aas-paas alag frame jaisa dikhta hai". Wajah — tile logo ko *fit* karta tha
// (poora dikhane ke liye), isliye square box me wide logo ke saath letterbox ki
// patti bachti thi.
//
// Ab: margin trim → centre **square crop** (cover) → tile ka poora area image.
// Ye test tile ke har kinare par content hone ki guarantee deta hai, PDF ke liye
// stored logo ka opaque JPEG rehna, aur purane letterbox tile ka one-time
// upgrade check karta hai.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const jpeg = require('jpeg-js');

const thumb = require('../src/thumb');

const px = (img, x, y) => {
  const i = (y * img.width + x) * 4;
  return [img.data[i], img.data[i + 1], img.data[i + 2]];
};
const decode = url => jpeg.decode(Buffer.from(String(url).split(',')[1], 'base64'), { useTArray: true });
const isWhite = ([r, g, b]) => r > 240 && g > 240 && b > 240;

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

// 1) Safed page + beech me wordmark (sabse common: letterhead scan / screenshot).
const PAGE_LOGO = encodeJpeg(900, 300, (d, w) => fill(d, w, 140, 90, 760, 210, [60, 70, 180]));
// 2) Brand plate wala logo (shop ne design karwaya hua) — kinare tak rang.
const BANNER_LOGO = encodeJpeg(800, 500, (d, w) => {
  fill(d, w, 0, 0, 800, 500, [24, 44, 160]);
  fill(d, w, 340, 190, 460, 330, [212, 232, 120]);
});

test('tile ka poora area content — koi patti ya safed padding nahi', () => {
  for (const [name, src] of [['page', PAGE_LOGO], ['banner', BANNER_LOGO]]) {
    const url = thumb.shopThumb(src);
    assert.match(url, /^data:image\/jpeg;base64,/, `${name}: thumbnail JPEG`);
    const img = decode(url);
    assert.deepEqual({ width: img.width, height: img.height }, { width: 128, height: 128 }, name);

    // Kinare (aur bilkul corners) par content ho — letterbox/padding kahin nahi.
    for (const [x, y] of [[1, 1], [126, 1], [1, 126], [126, 126], [64, 1], [1, 64], [126, 64], [64, 126]]) {
      if (name === 'banner') {
        // Plate wale logo me edge par bhi plate ka rang — patti nahi.
        const [r, g, b] = px(img, x, y);
        assert.ok(b > 100 && b > g && b > r, `${name}: edge par plate ka rang (${x},${y}): ${r},${g},${b}`);
      } else {
        assert.equal(isWhite(px(img, x, y)), false, `${name}: edge par safed padding nahi (${x},${y})`);
      }
    }
  }
});

test('wide logo ka centre square crop hota hai (scale bigda nahi)', () => {
  const img = decode(thumb.shopThumb(PAGE_LOGO));
  // 900x300 wordmark: trim ke baad ~620x120 (wide) → crop centre 120x120.
  // Tile me content ke rang wahi rehne chahiye (safed page ka margin nahi).
  let opaque = 0;
  for (let y = 0; y < 128; y++) for (let x = 0; x < 128; x++) {
    if (!isWhite(px(img, x, y))) opaque++;
  }
  assert.ok(opaque > 128 * 128 * 0.5, `tile ka bada hissa content ho: ${opaque}`);
});

test('stored 512 tile bhi full-bleed, PDF ke liye opaque JPEG', () => {
  const tiles = thumb.shopLogoTiles(PAGE_LOGO);
  assert.match(tiles.logo, /^data:image\/jpeg;base64,/);
  const logo = decode(tiles.logo);
  assert.deepEqual({ width: logo.width, height: logo.height }, { width: 512, height: 512 });
  const i = (256 * logo.width + 256) * 4;
  assert.equal(logo.data[i + 3], 255, 'JPEG ka alpha 255 hi hota hai');
  for (const [x, y] of [[3, 3], [508, 3], [3, 508], [508, 508]]) {
    assert.equal(isWhite(px(logo, x, y)), false, `512 tile ka corner bhara ho (${x},${y})`);
  }
});

test('naya tile dobara process karne par badalta nahi (idempotent)', () => {
  const once = thumb.shopLogoTiles(PAGE_LOGO);
  const again = thumb.shopLogoTiles(once.logo);
  assert.equal(again.logo, once.logo, 'normalized (512 square) tile recompress nahi hota');
  assert.equal(thumb.shopLogoTiles(BANNER_LOGO).logo, thumb.shopLogoTiles(thumb.shopLogoTiles(BANNER_LOGO).logo).logo);
});

test('purana letterbox tile `force` se naye crop me aata hai', () => {
  const fresh = thumb.shopLogoTiles(PAGE_LOGO).logo;
  const legacy = thumb.shopLogoTiles(fresh, { force: true });
  assert.ok(legacy, 'force ke saath tile banti hai');
  assert.match(legacy.logo, /^data:image\/jpeg;base64,/);
  assert.notEqual(legacy.logo, fresh, 'force par dobara crop hota hai (migration ke liye)');
});

test('wide wordmark ka poora text dikhta hai (backdrop + centre fit)', () => {
  // Safed page par likha wordmark: akshar kat ne nahi chahiye, aur box bhi bhara
  // rahe (backdrop = usi wordmark ka blur, upar poora wordmark).
  const wordmark = encodeJpeg(900, 260, (d, w) => {
    for (let k = 0; k < 5; k++) fill(d, w, 150 + k * 130, 110, 150 + k * 130 + 70, 190, [60, 70, 180]);
  });
  const img = decode(thumb.shopThumb(wordmark));
  assert.deepEqual({ width: img.width, height: img.height }, { width: 128, height: 128 });

  // Kinare bhi content (backdrop) — koi safed patti nahi.
  for (const [x, y] of [[1, 1], [126, 1], [1, 126], [126, 126]]) {
    assert.equal(isWhite(px(img, x, y)), false, `edge par backdrop (${x},${y})`);
  }
  // Beech ki row me wordmark ke bars ke rang maujood (text crop nahi hua).
  let bars = 0;
  for (let x = 0; x < 128; x++) {
    const [r, g, b] = px(img, x, 64);
    if (b > 110 && b > r + 40) bars++;
  }
  assert.ok(bars >= 4, `wordmark ke bars dikhein: ${bars}`);
});

test('square-ish logo par koi backdrop nahi — seedha cover', () => {
  const squareLogo = encodeJpeg(500, 500, (d, w) => {
    fill(d, w, 0, 0, 500, 500, [30, 90, 60]);
    fill(d, w, 200, 200, 300, 300, [230, 240, 120]);
  });
  const img = decode(thumb.shopThumb(squareLogo));
  const [r, g, b] = px(img, 2, 2);
  assert.ok(g > r && g > b && g < 120, `corner par plate ka rang: ${r},${g},${b}`);
});
