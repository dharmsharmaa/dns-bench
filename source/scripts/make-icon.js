#!/usr/bin/env node
/**
 * DNS Bench — icon renderer.
 *
 * Pure Node, zero dependencies: every shape is drawn by evaluating signed
 * distance fields per (super)sampled pixel, and the PNG is encoded here with
 * zlib + a hand rolled CRC32. No canvas, no sharp, no pngjs.
 *
 * Outputs (into ../app/resources):
 *   icon.png            1024x1024 app icon (squircle, navy→indigo, bars + accent dot)
 *   trayTemplate.png      22x22  menu bar template image (black + alpha only)
 *   trayTemplate@2x.png   44x44  @2x menu bar template image
 *
 * Usage:
 *   node make-icon.js           render every icon, print the paths
 *   node make-icon.js --check   validate dimensions of the existing icons
 */
'use strict';

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.join(__dirname, '..');
const RESOURCES = path.join(ROOT, 'app', 'resources');

const ICON_FILE = path.join(RESOURCES, 'icon.png');
const TRAY_FILE = path.join(RESOURCES, 'trayTemplate.png');
const TRAY_2X_FILE = path.join(RESOURCES, 'trayTemplate@2x.png');

/* ------------------------------------------------------------------ PNG -- */

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const head = Buffer.alloc(4);
  head.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([head, body, crc]);
}

function encodePNG(width, height, rgba) {
  const stride = width * 4 + 1;
  const raw = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    raw[y * stride] = 0; // filter: none
    raw.set(rgba.subarray(y * width * 4, (y + 1) * width * 4), y * stride + 1);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // colour type: RGBA
  ihdr[10] = 0; // deflate
  ihdr[11] = 0; // adaptive filtering
  ihdr[12] = 0; // no interlace

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

function pngInfo(file) {
  const buf = fs.readFileSync(file);
  const sig = buf.length >= 33 &&
    buf.readUInt32BE(0) === 0x89504e47 &&
    buf.readUInt32BE(4) === 0x0d0a1a0a;
  if (!sig) throw new Error(`${path.basename(file)} is not a PNG`);
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
    depth: buf[24],
    colorType: buf[25],
    bytes: buf.length
  };
}

/* ----------------------------------------------------------------- math -- */

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const lerp = (a, b, t) => a + (b - a) * t;

function smoothstep(e0, e1, x) {
  const t = clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
}

// Signed distance (negative inside) -> anti-aliased coverage over `width` px.
function coverage(d, width) {
  return smoothstep(0, 1, clamp01(0.5 - d / width));
}

/**
 * Superellipse ("squircle") distance field. `n` controls corner continuity;
 * n = 3.7 yields a corner curvature radius of roughly 22% of the shape size,
 * which is the Big Sur / Apple squircle sweet spot.
 */
function squircleSDF(dx, dy, half, n) {
  const ax = Math.abs(dx) / half;
  const ay = Math.abs(dy) / half;
  if (ax < 1e-6 && ay < 1e-6) return -half;

  const px = Math.pow(ax, n);
  const py = Math.pow(ay, n);
  const f = px + py;
  const q = Math.pow(f, 1 / n);
  const g = q - 1;

  const inv = Math.pow(f, 1 / n - 1);
  let gx = 0;
  let gy = 0;
  if (ax > 1e-6) gx = (inv * n * Math.pow(ax, n - 1) * Math.sign(dx)) / half;
  if (ay > 1e-6) gy = (inv * n * Math.pow(ay, n - 1) * Math.sign(dy)) / half;
  const gl = Math.hypot(gx, gy);
  if (gl < 1e-9) return -half;

  return g / gl;
}

function roundRectSDF(x, y, cx, cy, hw, hh, r) {
  const qx = Math.abs(x - cx) - (hw - r);
  const qy = Math.abs(y - cy) - (hh - r);
  return (
    Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) +
    Math.min(Math.max(qx, qy), 0) -
    r
  );
}

/* ------------------------------------------------------------ app icon -- */

const DESIGN = 1024;
const CENTER = DESIGN / 2;
const SHAPE_HALF = 412;          // 824px squircle on a 1024 canvas (100px macOS padding)
const SQUIRCLE_N = 3.7;

const BAR_W = 104;
const BAR_GAP = 44;
const BAR_BASE = 706;
const BAR_HEIGHTS = [180, 306, 432];
const BAR_CENTERS = [
  CENTER - (BAR_W + BAR_GAP),
  CENTER,
  CENTER + (BAR_W + BAR_GAP)
];

const DOT_R = 32;
const DOT_CX = CENTER + (BAR_W + BAR_GAP);
const DOT_CY = BAR_BASE - BAR_HEIGHTS[2] - 52 - DOT_R;

const SHADOW_R = 0.014;
const SHADOW_G = 0.019;
const SHADOW_B = 0.043;

function iconShade(x, y) {
  const dx = x - CENTER;
  const dy = y - CENTER;

  const d = squircleSDF(dx, dy, SHAPE_HALF, SQUIRCLE_N);
  const shapeA = coverage(d, 1);

  // Soft drop shadow: the same squircle sampled 16px lower, blurred.
  let shadowA = 0;
  if (shapeA < 0.999) {
    const ds = squircleSDF(dx, dy - 16, SHAPE_HALF, SQUIRCLE_N);
    const spread = Math.max(0, ds) / 24;
    const falloff = 0.58 + 0.42 * smoothstep(-1, 1, dy / SHAPE_HALF);
    shadowA = 0.27 * Math.exp(-0.5 * spread * spread) * falloff;
  }

  if (shapeA <= 0 && shadowA <= 0.002) return [0, 0, 0, 0];

  const nx = dx / SHAPE_HALF;
  const ny = dy / SHAPE_HALF;

  // Navy -> indigo body, very slightly lit from the upper left.
  let t = clamp01(0.5 + 0.55 * ny + 0.1 * nx);
  t = t * t * (3 - 2 * t);

  let r = lerp(0.051, 0.196, t);
  let g = lerp(0.078, 0.184, t);
  let b = lerp(0.188, 0.552, t);

  // Top specular pool + a narrow sheen band just under the top rim.
  const hx = dx / 430;
  const hy = (dy + 212) / 300;
  const spec = 0.15 * Math.exp(-1.3 * (hx * hx + hy * hy));
  const sheen = 0.042 * Math.exp(-Math.pow((dy + 366) / 52, 2)) *
    Math.exp(-Math.pow(dx / 330, 6));
  r += spec + sheen;
  g += spec * 1.03 + sheen;
  b += spec * 1.14 + sheen * 1.05;

  // Soft inner shadow pooling along the bottom edge.
  const lower = clamp01((ny + 0.1) / 1.1);
  let dark = 0.26 * Math.pow(lower, 2);
  const depth = Math.max(0, -d);
  dark += 0.28 * Math.exp(-depth / 22) * smoothstep(0.1, 1.15, ny);
  dark = Math.min(0.56, dark);
  r *= 1 - dark;
  g *= 1 - dark * 0.96;
  b *= 1 - dark * 0.82;

  // Benchmark bars — three white rounded capsules, ascending.
  let barA = 0;
  if (x > 292 && x < 732 && y > 244 && y < 720) {
    let db = Infinity;
    for (let i = 0; i < 3; i++) {
      const h = BAR_HEIGHTS[i];
      db = Math.min(
        db,
        roundRectSDF(x, y, BAR_CENTERS[i], BAR_BASE - h / 2, BAR_W / 2, h / 2, BAR_W / 2)
      );
    }
    barA = coverage(db, 1);
    if (barA > 0) {
      const bt = clamp01((y - (BAR_BASE - BAR_HEIGHTS[2])) / 470);
      const br = lerp(1, 0.865, bt);
      const bg = lerp(1, 0.9, bt);
      const bb = lerp(1, 0.995, bt);
      r = lerp(r, br, barA);
      g = lerp(g, bg, barA);
      b = lerp(b, bb, barA);
    }
  }

  // Accent dot, floating above the tallest bar.
  if (x > DOT_CX - DOT_R - 3 && x < DOT_CX + DOT_R + 3 &&
      y > DOT_CY - DOT_R - 3 && y < DOT_CY + DOT_R + 3) {
    const dotA = coverage(Math.hypot(x - DOT_CX, y - DOT_CY) - DOT_R, 1);
    if (dotA > 0) {
      const dt = clamp01((y - (DOT_CY - DOT_R)) / (DOT_R * 2));
      r = lerp(r, lerp(0.42, 0.12, dt), dotA);
      g = lerp(g, lerp(0.87, 0.58, dt), dotA);
      b = lerp(b, lerp(1.0, 1.0, dt), dotA);
    }
  }

  // 1pt inner light rim (2px on the 1024 canvas): bright at the top, fading down.
  const rimW = 2.2;
  const rimT = clamp01(1 - Math.abs(d + rimW / 2) / (rimW / 2));
  if (rimT > 0) {
    const vm = clamp01(0.5 - 0.44 * ny);
    const ra = 0.5 * vm * rimT;
    r = lerp(r, 0.85, ra);
    g = lerp(g, 0.9, ra);
    b = lerp(b, 1, ra);
  }

  const a = shapeA + shadowA * (1 - shapeA);
  return [
    r * shapeA + SHADOW_R * shadowA * (1 - shapeA),
    g * shapeA + SHADOW_G * shadowA * (1 - shapeA),
    b * shapeA + SHADOW_B * shadowA * (1 - shapeA),
    a
  ];
}

/* ----------------------------------------------------------- tray icon -- */

// Design space is 22pt regardless of the rendered resolution.
const TRAY_SIZE = 22;
const TRAY_BAR_W = 3.5;
const TRAY_GAP = 2.25;
const TRAY_BASE = 17.7;
const TRAY_HEIGHTS = [6.6, 9.9, 13.2];
const TRAY_LEFT = (TRAY_SIZE - (3 * TRAY_BAR_W + 2 * TRAY_GAP)) / 2;

function trayShade(x, y) {
  let d = Infinity;
  for (let i = 0; i < 3; i++) {
    const h = TRAY_HEIGHTS[i];
    const cx = TRAY_LEFT + TRAY_BAR_W / 2 + i * (TRAY_BAR_W + TRAY_GAP);
    d = Math.min(
      d,
      roundRectSDF(x, y, cx, TRAY_BASE - h / 2, TRAY_BAR_W / 2, h / 2, TRAY_BAR_W / 2)
    );
  }
  const a = coverage(d, 0.85);
  return [0, 0, 0, a];
}

/* ------------------------------------------------------------- raster -- */

function render(shade, size, ss, designSize) {
  const W = size * ss;
  const step = designSize / W;
  const buf = new Float32Array(W * W * 4);

  for (let py = 0; py < W; py++) {
    const y = (py + 0.5) * step;
    for (let px = 0; px < W; px++) {
      const c = shade((px + 0.5) * step, y);
      if (c[3] === 0) continue;
      const i = (py * W + px) * 4;
      buf[i] = c[0];
      buf[i + 1] = c[1];
      buf[i + 2] = c[2];
      buf[i + 3] = c[3];
    }
  }

  // Box-filter down to the target resolution in premultiplied space.
  const out = new Uint8Array(size * size * 4);
  const inv = 1 / (ss * ss);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      for (let sy = 0; sy < ss; sy++) {
        for (let sx = 0; sx < ss; sx++) {
          const i = ((y * ss + sy) * W + (x * ss + sx)) * 4;
          r += buf[i];
          g += buf[i + 1];
          b += buf[i + 2];
          a += buf[i + 3];
        }
      }
      r *= inv;
      g *= inv;
      b *= inv;
      a *= inv;

      const o = (y * size + x) * 4;
      if (a <= 0.0005) continue;
      out[o] = Math.round(clamp01(r / a) * 255);
      out[o + 1] = Math.round(clamp01(g / a) * 255);
      out[o + 2] = Math.round(clamp01(b / a) * 255);
      out[o + 3] = Math.round(clamp01(a) * 255);
    }
  }
  return out;
}

function writeIcon(file, shade, size, ss, designSize) {
  const pixels = render(shade, size, ss, designSize);
  fs.writeFileSync(file, encodePNG(size, size, pixels));
  return file;
}

const TARGETS = [
  { file: ICON_FILE, size: DESIGN, ss: 2, shade: iconShade, designSize: DESIGN },
  { file: TRAY_FILE, size: 22, ss: 8, shade: trayShade, designSize: TRAY_SIZE },
  { file: TRAY_2X_FILE, size: 44, ss: 6, shade: trayShade, designSize: TRAY_SIZE }
];

function renderAll() {
  fs.mkdirSync(RESOURCES, { recursive: true });
  for (const target of TARGETS) {
    writeIcon(target.file, target.shade, target.size, target.ss, target.designSize);
    const info = pngInfo(target.file);
    console.log(`${target.file}  ${info.width}x${info.height}  ${info.bytes} bytes`);
  }
}

function check() {
  let ok = true;
  for (const target of TARGETS) {
    if (!fs.existsSync(target.file)) {
      console.log(`${target.file}  missing`);
      ok = false;
      continue;
    }
    const info = pngInfo(target.file);
    const good = info.width === target.size && info.height === target.size && info.colorType === 6;
    console.log(
      `${target.file}  ${info.width}x${info.height}  rgba8  ${good ? 'ok' : 'MISMATCH'}`
    );
    if (!good) ok = false;
  }
  return ok;
}

/* ---------------------------------------------------------------- main -- */

const wantsCheck = process.argv.includes('--check');

if (wantsCheck) {
  const missing = TARGETS.some((t) => !fs.existsSync(t.file));
  if (missing) {
    console.log('icons missing — rendering before validation');
    renderAll();
    console.log('');
  }
  if (!check()) process.exit(1);
  console.log('icons valid');
} else {
  renderAll();
}
