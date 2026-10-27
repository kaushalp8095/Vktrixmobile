// TINY PNG ENCODER (RGBA, alpha ke saath)
//
// Shop logo ka thumbnail pehle JPEG tha — JPEG me transparency hoti hi nahi,
// isliye logo ke aas-paas safed box dark theme me alag dikhta tha ("box me white
// bg dikh raha hai"). Ab thumbnail PNG hai: margin transparent, logo sirf apne
// shape me dikhta hai aur app ka tile usko apne background par baitha leta hai.
//
// Sirf 128px thumbnails ke liye hai (small), isliye seedha non-interlaced PNG,
// filter 0 (None) aur zlib deflate — dependency ke bina, Node ke zlib se.
const zlib = require('node:zlib');

const hasCrc32 = typeof zlib.crc32 === 'function';

// Purane Node ke liye CRC32 table (Render par Node 22 hai, par test/local alag
// ho sakta hai — dono raste chalne chahiye).
let table = null;
function crc32Fallback(buf) {
  if (!table) {
    table = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c;
    }
  }
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xff];
  return (crc ^ -1) >>> 0;
}

const crc32 = buf => (hasCrc32 ? zlib.crc32(buf) >>> 0 : crc32Fallback(buf));

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([length, typeBuf, data, crc]);
}

/// PNG filter — `f` 0..4 (None, Sub, Up, Average, Paeth).
function filterRow(f, row, prev, firstRow) {
  const n = row.length;
  const out = Buffer.alloc(n);
  for (let i = 0; i < n; i++) {
    const a = i >= 4 ? row[i - 4] : 0;      // left
    const b = prev[i];                      // up
    const c = i >= 4 ? prev[i - 4] : 0;     // up-left
    let v;
    switch (f) {
      case 1: v = row[i] - a; break;
      case 2: v = firstRow ? row[i] : row[i] - b; break;
      case 3: v = row[i] - ((a + b) >> 1); break;
      case 4: {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        const pred = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
        v = row[i] - pred;
        break;
      }
      default: v = row[i];
    }
    out[i] = v & 0xff;
  }
  return out;
}

/// RGBA bytes (width*height*4) → PNG buffer.
function encodePng(rgba, width, height) {
  if (!rgba || !width || !height) throw new Error('invalid image');
  if (rgba.length < width * height * 4) throw new Error('pixel buffer too small');

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // colour type: truecolour + alpha
  ihdr[10] = 0;  // compression
  ihdr[11] = 0;  // filter
  ihdr[12] = 0;  // interlace

  // Har row ke liye adaptive filter (PNG spec ke 5 me se sabse chhota) —
  // photo-jaisi logos bhi 128px par ~30 KB ke andar reh jaate hain.
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  const zero = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const row = rgba.subarray(y * stride, (y + 1) * stride);
    const prev = y === 0 ? zero : rgba.subarray((y - 1) * stride, y * stride);
    let bestFilter = 0, best = null, bestScore = Infinity;
    for (let f = 0; f <= 4; f++) {
      const out = filterRow(f, row, prev, y === 0);
      let score = 0;
      for (let i = 0; i < out.length; i++) { const v = out[i]; score += v < 128 ? v : 256 - v; }
      if (score < bestScore) { bestScore = score; best = out; bestFilter = f; }
    }
    raw[y * (stride + 1)] = bestFilter;
    best.copy(raw, y * (stride + 1) + 1);
  }

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

module.exports = { encodePng, crc32, filterRow };
