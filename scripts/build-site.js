#!/usr/bin/env node
/* build-site.js — prépare le SITE DIRECTION (web/) pour la mise en ligne.
   Usage :  node scripts/build-site.js            → crée dist/site/
            node scripts/build-site.js --out <dossier> --config <chemin config.js>   (tests)
   Ce que fait le script :
     1. vérifie web/config.js : URL Supabase + clé « anon » (REFUSE une clé service_role) ;
     2. copie web/ → dist/site/ sans les tests ni config.example.js ;
     3. écrit _headers (Netlify et Cloudflare Pages) : CSP stricte calculée d'après l'URL
        Supabase, anti-iframe, pas d'indexation, pas de cache périmé ;
     4. écrit robots.txt (site interne : ne pas indexer).
   Aucun envoi réseau : le dépôt chez l'hébergeur se fait ensuite (voir docs/mise-en-ligne.md). */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'web');
const arg = (name) => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : null; };
const OUT = path.resolve(arg('--out') || path.join(ROOT, 'dist', 'site'));
const CONFIG = path.resolve(arg('--config') || path.join(WEB, 'config.js'));
const EXCLUDE = new Set(['tests', 'config.example.js', 'config.js']);

function fail(msg) { console.error('\n✗ ' + msg + '\n'); process.exit(1); }

// ---------------------------------------------------------------- 1. configuration
// Sur Netlify (dépôt GitHub) : web/config.js n'est pas versionné → on le génère à partir des
// variables d'environnement SUPABASE_URL et SUPABASE_KEY (Site configuration → Environment variables).
let configSrc;
if (process.env.SUPABASE_URL && process.env.SUPABASE_KEY && !arg('--config')) {
  configSrc = '// Généré par scripts/build-site.js à partir des variables d\'environnement.\n' +
    'window.ELIKYA_CONFIG = ' + JSON.stringify({ url: process.env.SUPABASE_URL.trim(), anonKey: process.env.SUPABASE_KEY.trim() }) + ';\n';
  console.log('Configuration lue depuis SUPABASE_URL / SUPABASE_KEY.');
} else {
  if (!fs.existsSync(CONFIG)) fail('web/config.js introuvable : copie web/config.example.js en web/config.js et colle la clé anon' +
    ' (ou définis SUPABASE_URL et SUPABASE_KEY, ex. dans les variables Netlify).');
  configSrc = fs.readFileSync(CONFIG, 'utf8');
}
const sandbox = { window: {} };
try { vm.runInNewContext(configSrc, sandbox); } catch (e) { fail('config.js illisible : ' + e.message); }
const cfg = sandbox.window.ELIKYA_CONFIG || {};
let url;
try { url = new URL(cfg.url); } catch { fail('config.js : url Supabase invalide.'); }
if (url.protocol !== 'https:' && url.hostname !== '127.0.0.1' && url.hostname !== 'localhost') fail('config.js : l’URL Supabase doit être en https.');
const key = String(cfg.anonKey || '');
if (!key || key.startsWith('COLLE_TA')) fail('config.js : la clé anon n’est pas renseignée.');
// Clé JWT (eyJ…) : le rôle doit être « anon ». Nouvelles clés Supabase : sb_publishable_… OK, sb_secret_… refusée.
if (key.startsWith('sb_secret_')) fail('config.js contient une clé SECRÈTE (sb_secret_…). Mets la clé publishable / anon, jamais la secrète.');
if (key.startsWith('eyJ')) {
  let role = null;
  try { role = JSON.parse(Buffer.from(key.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString()).role; } catch { /* clé illisible */ }
  if (role === 'service_role') fail('config.js contient la clé service_role (accès total à la base). Mets la clé anon.');
  if (role !== 'anon') fail('config.js : clé inattendue (rôle « ' + role + ' »). Mets la clé anon.');
}

// ---------------------------------------------------------------- 2. copie
fs.rmSync(OUT, { recursive: true, force: true });
function copy(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    if (src === WEB && EXCLUDE.has(e.name)) continue;
    const s = path.join(src, e.name), d = path.join(dst, e.name);
    e.isDirectory() ? copy(s, d) : fs.copyFileSync(s, d);
  }
}
copy(WEB, OUT);
fs.writeFileSync(path.join(OUT, 'config.js'), configSrc);
if (!fs.existsSync(path.join(OUT, 'vendor', 'supabase.js'))) fail('web/vendor/supabase.js manquant.');

// ---------------------------------------------------------------- 3. en-têtes de sécurité
// Empreintes des <script> en ligne de index.html (pas de 'unsafe-inline' pour les scripts)
const html = fs.readFileSync(path.join(OUT, 'index.html'), 'utf8');
const hashes = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)]
  .map((m) => "'sha256-" + crypto.createHash('sha256').update(m[1]).digest('base64') + "'");
const supa = url.origin, ws = supa.replace(/^http/, 'ws');
const csp = [
  "default-src 'self'",
  "script-src 'self' https://cdn.jsdelivr.net " + hashes.join(' '),
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  'font-src https://fonts.gstatic.com',
  "connect-src 'self' " + supa + ' ' + ws,
  "img-src 'self' data: blob:",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
].join('; ');
fs.writeFileSync(path.join(OUT, '_headers'), [
  '/*',
  '  Content-Security-Policy: ' + csp,
  '  X-Frame-Options: DENY',
  '  X-Content-Type-Options: nosniff',
  '  Referrer-Policy: strict-origin-when-cross-origin',
  '  Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()',
  '  X-Robots-Tag: noindex, nofollow',
  '  Cache-Control: no-cache',
  '',
].join('\n'));

// ---------------------------------------------------------------- 4. robots.txt
fs.writeFileSync(path.join(OUT, 'robots.txt'), 'User-agent: *\nDisallow: /\n');

const n = (function count(d) { return fs.readdirSync(d, { withFileTypes: true }).reduce((a, e) => a + (e.isDirectory() ? count(path.join(d, e.name)) : 1), 0); })(OUT);
console.log('✓ Site prêt : ' + path.relative(ROOT, OUT) + ' (' + n + ' fichiers)');
console.log('  Supabase : ' + supa + '  ·  clé : ' + (key.startsWith('eyJ') ? 'anon (JWT)' : 'publishable'));
console.log('  Étape suivante : déposer ce dossier chez l’hébergeur (docs/mise-en-ligne.md).');
