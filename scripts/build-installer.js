#!/usr/bin/env node
/* build-installer.js — fabrique l'installeur Windows de l'app agents.
   Usage :  node scripts/build-installer.js            (compile l'app puis l'installeur)
            node scripts/build-installer.js --no-build (réutilise la dernière compilation)
   Sortie : dist/Elikya-Agents-Setup-<version>.exe
   Étapes :
     1. vérifie agents/lib/config.dart (clé publishable / anon, jamais une clé secrète) ;
     2. flutter build windows --release ;
     3. trouve le runtime Visual C++ redistribuable (Visual Studio) et NSIS (makensis) ;
     4. compile agents/installer/elikya-agents.nsi.
   Version : celle de agents/pubspec.yaml (« version: 1.2.0+5 » → 1.2.0). L'augmenter avant
   chaque nouvelle diffusion pour que Windows affiche la bonne version. */
const fs = require('fs');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const AGENTS = path.join(ROOT, 'agents');
const DIST = path.join(ROOT, 'dist');
const fail = (m) => { console.error('\n✗ ' + m + '\n'); process.exit(1); };

// ---------------------------------------------------------------- 1. config + version
const cfgPath = path.join(AGENTS, 'lib', 'config.dart');
if (!fs.existsSync(cfgPath)) fail('agents/lib/config.dart introuvable : copie config.example.dart en config.dart et colle la clé.');
const cfg = fs.readFileSync(cfgPath, 'utf8');
const key = (cfg.match(/supabaseAnonKey\s*=\s*'([^']*)'/) || [])[1] || '';
if (!key || key.startsWith('COLLE_TA')) fail('agents/lib/config.dart : clé non renseignée.');
if (key.startsWith('sb_secret_')) fail('agents/lib/config.dart contient une clé SECRÈTE : elle serait lisible dans l’exe. Mets la clé publishable.');
if (key.startsWith('eyJ')) {
  let role = null;
  try { role = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role; } catch { /* illisible */ }
  if (role !== 'anon') fail('agents/lib/config.dart : clé de rôle « ' + role + ' ». Mets la clé anon / publishable.');
}
const pub = fs.readFileSync(path.join(AGENTS, 'pubspec.yaml'), 'utf8');
const m = pub.match(/^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?/m);
if (!m) fail('version introuvable dans agents/pubspec.yaml');
const VERSION = `${m[1]}.${m[2]}.${m[3]}`, VERSION4 = `${VERSION}.${m[4] || 0}`;

// ---------------------------------------------------------------- 2. compilation Flutter
const RELEASE = path.join(AGENTS, 'build', 'windows', 'x64', 'runner', 'Release');
if (!process.argv.includes('--no-build')) {
  console.log('Compilation de l’app (flutter build windows --release)…');
  const r = spawnSync('flutter build windows --release', { cwd: AGENTS, stdio: 'inherit', shell: true });
  if (r.status !== 0) fail('La compilation Flutter a échoué.');
}
if (!fs.existsSync(path.join(RELEASE, 'elikya_agents.exe'))) fail('elikya_agents.exe introuvable : lance sans --no-build.');

// ---------------------------------------------------------------- 3. outils
function findCrt() {
  if (process.env.VC_CRT_DIR) return process.env.VC_CRT_DIR;
  const roots = ['C:/Program Files/Microsoft Visual Studio', 'C:/Program Files (x86)/Microsoft Visual Studio'];
  const found = [];
  const walk = function (d, depth) {
    if (depth > 8 || !fs.existsSync(d)) return;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      const p = path.join(d, e.name);
      if (/^Microsoft\.VC\d+\.CRT$/i.test(e.name) && /[\\/]x64[\\/]/i.test(p) && !/onecore|debug|spectre/i.test(p)) found.push(p);
      else walk(p, depth + 1);
    }
  };
  roots.forEach((r) => walk(r, 0));
  return found.sort().pop();
}
const CRT = findCrt();
if (!CRT || !['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'].every((f) => fs.existsSync(path.join(CRT, f))))
  fail('Runtime Visual C++ introuvable (Visual Studio → VC\\Redist\\MSVC\\…\\x64\\Microsoft.VC*.CRT). Indique-le avec VC_CRT_DIR.');

function findNsis() {
  const c = [process.env.MAKENSIS, 'C:/src/nsis-3.10/makensis.exe', 'C:/Program Files (x86)/NSIS/makensis.exe', 'C:/Program Files/NSIS/makensis.exe'];
  for (const p of c) if (p && fs.existsSync(p)) return p;
  const w = spawnSync('where makensis', { shell: true, encoding: 'utf8' });
  return w.status === 0 ? w.stdout.split(/\r?\n/)[0].trim() : null;
}
const MAKENSIS = findNsis();
if (!MAKENSIS) fail('NSIS (makensis) introuvable. Installe NSIS 3 ou indique son chemin avec MAKENSIS.');

// ---------------------------------------------------------------- 4. installeur
fs.mkdirSync(DIST, { recursive: true });
const OUTFILE = path.join(DIST, `Elikya-Agents-Setup-${VERSION}.exe`);
const ICON = path.join(AGENTS, 'windows', 'runner', 'resources', 'app_icon.ico');
console.log(`Installeur ${VERSION} (NSIS : ${MAKENSIS})`);
try {
  execFileSync(MAKENSIS, ['/V2', '/INPUTCHARSET', 'UTF8',
    `/DVERSION=${VERSION}`, `/DVERSION4=${VERSION4}`, `/DSRC=${RELEASE}`, `/DCRT=${CRT}`,
    `/DICON=${ICON}`, `/DOUTFILE=${OUTFILE}`, path.join(AGENTS, 'installer', 'elikya-agents.nsi')], { stdio: 'inherit' });
} catch { fail('La compilation NSIS a échoué.'); }
const mo = (fs.statSync(OUTFILE).size / 1048576).toFixed(1);
console.log(`\n✓ ${path.relative(ROOT, OUTFILE)} (${mo} Mo) — à copier sur les postes des agents et à double-cliquer.`);
