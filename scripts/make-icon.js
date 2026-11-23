#!/usr/bin/env node
/* make-icon.js — assemble l'icône Windows de l'app agents à partir du LOGO OFFICIEL
   (emblème Elikya Group : avion orange sur carré marine, cf. Elikya-Group-Dossier/02_logos).
   Entrée : agents/assets/brand/mark-<taille>.png (rendus fidèles de elikya-mark.svg, non retouchés)
   Sortie : agents/windows/runner/resources/app_icon.ico (16 → 256 px, PNG dans ICO)
   Usage  : node scripts/make-icon.js
   Pour régénérer les PNG depuis le SVG : ouvrir elikya-mark.svg dans un navigateur et l'exporter
   aux tailles 16, 24, 32, 48, 64, 128, 256 (canvas drawImage), sans recolorer ni déformer. */
const fs = require('fs');
const path = require('path');

const BRAND = path.join(__dirname, '..', 'agents', 'assets', 'brand');
const OUT = path.join(__dirname, '..', 'agents', 'windows', 'runner', 'resources', 'app_icon.ico');
const SIZES = [16, 24, 32, 48, 64, 128, 256];

const images = SIZES.map((s) => {
  const f = path.join(BRAND, `mark-${s}.png`);
  if (!fs.existsSync(f)) { console.error('✗ ' + f + ' manquant'); process.exit(1); }
  const data = fs.readFileSync(f);
  if (data.readUInt32BE(16) !== s || data.readUInt32BE(20) !== s) { console.error('✗ ' + f + ' : taille ≠ ' + s + ' px'); process.exit(1); }
  return { s, data };
});

const head = Buffer.alloc(6); head.writeUInt16LE(0, 0); head.writeUInt16LE(1, 2); head.writeUInt16LE(images.length, 4);
let offset = 6 + 16 * images.length;
const dir = images.map(({ s, data }) => {
  const e = Buffer.alloc(16);
  e[0] = s === 256 ? 0 : s; e[1] = s === 256 ? 0 : s; e.writeUInt16LE(1, 4); e.writeUInt16LE(32, 6);
  e.writeUInt32LE(data.length, 8); e.writeUInt32LE(offset, 12); offset += data.length;
  return e;
});
fs.writeFileSync(OUT, Buffer.concat([head, ...dir, ...images.map((i) => i.data)]));
console.log('✓ ' + path.relative(process.cwd(), OUT) + ' depuis le logo officiel (' + SIZES.join(', ') + ' px)');
