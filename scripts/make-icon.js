#!/usr/bin/env node
/* make-icon.js — génère l'icône Windows de l'app agents (monogramme « E » doré sur graphite,
   même identité que le site). Aucune dépendance : rendu vectoriel simple + encodeur PNG/ICO.
   Usage : node scripts/make-icon.js [--png apercu.png]
   Sortie : agents/windows/runner/resources/app_icon.ico (16 → 256 px) */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const OUT = path.join(__dirname, '..', 'agents', 'windows', 'runner', 'resources', 'app_icon.ico');
const SIZES = [16, 24, 32, 48, 64, 128, 256];
const BG = [0x17, 0x18, 0x1a], GOLD = [0xca, 0xa2, 0x4e];

// Forme dans un repère 0..1 : renvoie [r,g,b,a] ou null (transparent)
function shade(x, y, s) {
  const R = 0.2, inset = 0.03;                       // coins arrondis
  const inRound = (x0, y0, x1, y1, r) => {
    if (x < x0 || x > x1 || y < y0 || y > y1) return false;
    const cx = Math.min(Math.max(x, x0 + r), x1 - r), cy = Math.min(Math.max(y, y0 + r), y1 - r);
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
  };
  if (!inRound(inset, inset, 1 - inset, 1 - inset, R)) return null;
  // liseré doré (masqué en très petite taille, illisible)
  const b = s >= 32 ? 0.035 : 0;
  if (b && !inRound(inset + b, inset + b, 1 - inset - b, 1 - inset - b, R - b)) return GOLD;
  // « E » : fût vertical + 3 barres (celle du milieu plus courte)
  const t = s <= 24 ? 0.15 : 0.12;                   // épaisseur, plus forte en petite taille
  const L = 0.3, Rt = 0.72, T = 0.24, B = 0.76, mid = 0.5;
  const inE =
    (x >= L && x <= L + t && y >= T && y <= B) ||
    (x >= L && x <= Rt && y >= T && y <= T + t) ||
    (x >= L && x <= Rt && y >= B - t && y <= B) ||
    (x >= L && x <= Rt - 0.07 && y >= mid - t / 2 && y <= mid + t / 2);
  return inE ? GOLD : BG;
}

function render(s) {
  const SS = 4, px = Buffer.alloc(s * s * 4);
  for (let j = 0; j < s; j++) for (let i = 0; i < s; i++) {
    let r = 0, g = 0, bl = 0, a = 0;
    for (let v = 0; v < SS; v++) for (let u = 0; u < SS; u++) {
      const c = shade((i + (u + 0.5) / SS) / s, (j + (v + 0.5) / SS) / s, s);
      if (c) { r += c[0]; g += c[1]; bl += c[2]; a++; }
    }
    const o = (j * s + i) * 4, n = SS * SS;
    if (a) { px[o] = Math.round(r / a); px[o + 1] = Math.round(g / a); px[o + 2] = Math.round(bl / a); }
    px[o + 3] = Math.round((a / n) * 255);
  }
  return px;
}

const CRC = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
function crc32(buf) { let c = -1; for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ -1) >>> 0; }
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]), crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(s, px) {
  const raw = Buffer.alloc(s * (s * 4 + 1));
  for (let j = 0; j < s; j++) { raw[j * (s * 4 + 1)] = 0; px.copy(raw, j * (s * 4 + 1) + 1, j * s * 4, (j + 1) * s * 4); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(s, 0); ihdr.writeUInt32BE(s, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

const images = SIZES.map((s) => ({ s, data: png(s, render(s)) }));
const head = Buffer.alloc(6); head.writeUInt16LE(0, 0); head.writeUInt16LE(1, 2); head.writeUInt16LE(images.length, 4);
let offset = 6 + 16 * images.length;
const dir = images.map(({ s, data }) => {
  const e = Buffer.alloc(16);
  e[0] = s === 256 ? 0 : s; e[1] = s === 256 ? 0 : s; e.writeUInt16LE(1, 4); e.writeUInt16LE(32, 6);
  e.writeUInt32LE(data.length, 8); e.writeUInt32LE(offset, 12); offset += data.length;
  return e;
});
fs.writeFileSync(OUT, Buffer.concat([head, ...dir, ...images.map((i) => i.data)]));
console.log('✓ ' + path.relative(process.cwd(), OUT) + ' (' + SIZES.join(', ') + ' px)');

const i = process.argv.indexOf('--png');
if (i > 0) { // aperçu : toutes les tailles côte à côte
  const W = SIZES.reduce((a, s) => a + s + 8, 8), H = 256 + 16, px = Buffer.alloc(W * H * 4, 0xff);
  let x0 = 8;
  for (const s of SIZES) { const p = render(s); for (let j = 0; j < s; j++) for (let k = 0; k < s; k++) {
    const o = (j * s + k) * 4, d = ((8 + j) * W + x0 + k) * 4, a = p[o + 3] / 255;
    for (let c = 0; c < 3; c++) px[d + c] = Math.round(p[o + c] * a + 255 * (1 - a));
  } x0 += s + 8; }
  // PNG non carré : en-tête dédié
  const raw = Buffer.alloc(H * (W * 4 + 1));
  for (let j = 0; j < H; j++) px.copy(raw, j * (W * 4 + 1) + 1, j * W * 4, (j + 1) * W * 4);
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 6;
  fs.writeFileSync(process.argv[i + 1], Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}
