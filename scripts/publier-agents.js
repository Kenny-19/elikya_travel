/* publier-agents.js — publie une nouvelle version de l'app des agents pour la MISE À JOUR À DISTANCE.
   Usage :   node scripts/publier-agents.js --notes "Ce qui change, en une ou deux phrases"
   Étapes :
     1. vérifie que l'outil GitHub (gh) est installé et connecté, et que le code est poussé ;
     2. construit l'installeur (scripts/build-installer.js) avec la version de agents/pubspec.yaml ;
     3. calcule son empreinte SHA-256 et écrit dist/agents.json (le « manifeste ») ;
     4. crée la Release GitHub v<version> (installeur + manifeste), marquée « dernière ».
   Les applications installées lisent .../releases/latest/download/agents.json (au démarrage puis
   toutes les 3 h) et proposent « Mettre à jour maintenant ». Voir agents/lib/data/mise_a_jour.dart.
   Avant chaque publication : augmenter « version: » dans agents/pubspec.yaml (ex. 1.6.0+8 → 1.6.1+9),
   le chiffre après « + » doit TOUJOURS augmenter. */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync, execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const AGENTS = path.join(ROOT, 'agents');
const DIST = path.join(ROOT, 'dist');
const REPO = 'Kenny-19/elikya_travel';
const RELEASES = `https://github.com/${REPO}/releases/`;
const fail = (m) => { console.error('\n✗ ' + m + '\n'); process.exit(1); };

// ---------------------------------------------------------------- arguments
const i = process.argv.indexOf('--notes');
const notes = i > 0 ? (process.argv[i + 1] || '').trim() : '';
if (!notes) fail('Indique ce qui change : node scripts/publier-agents.js --notes "Correction du solde mobile money"');

// ---------------------------------------------------------------- outil GitHub
function findGh() {
  for (const c of ['gh', 'C:/Program Files/GitHub CLI/gh.exe', path.join(process.env.LOCALAPPDATA || '', 'Programs/GitHub CLI/gh.exe')]) {
    const r = spawnSync(c, ['--version'], { encoding: 'utf8' });
    if (r.status === 0) return c;
  }
  return null;
}
const GH = findGh();
if (!GH) fail('Outil GitHub (gh) introuvable. Installe-le une fois : winget install --id GitHub.cli  puis : gh auth login');
if (spawnSync(GH, ['auth', 'status'], { encoding: 'utf8' }).status !== 0) fail('gh n’est pas connecté à GitHub : lance  gh auth login  (une seule fois).');
const gh = (args, opts) => execFileSync(GH, args, Object.assign({ encoding: 'utf8', cwd: ROOT }, opts));

// ---------------------------------------------------------------- version
const pub = fs.readFileSync(path.join(AGENTS, 'pubspec.yaml'), 'utf8');
const m = pub.match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)/m);
if (!m) fail('agents/pubspec.yaml : la version doit avoir la forme 1.6.0+8 (le +8 = numéro de build).');
const VERSION = m[1], BUILD = Number(m[2]), TAG = 'v' + VERSION;
if (spawnSync(GH, ['release', 'view', TAG, '--repo', REPO], { encoding: 'utf8' }).status === 0) {
  fail(`La version ${VERSION} est déjà publiée. Augmente « version: » dans agents/pubspec.yaml (ex. ${VERSION}+${BUILD} → x.y.z+${BUILD + 1}).`);
}
try {
  const derniere = JSON.parse(gh(['release', 'view', '--repo', REPO, '--json', 'tagName']).trim() || '{}');
  if (derniere.tagName) console.log(`Dernière version publiée : ${derniere.tagName}`);
} catch { console.log('Première publication.'); }

// le code de la version doit être sur GitHub (la Release pointe sur la branche main)
spawnSync('git', ['fetch', '-q', 'origin'], { cwd: ROOT });
const enAvance = spawnSync('git', ['rev-list', '--count', 'origin/main..HEAD'], { cwd: ROOT, encoding: 'utf8' }).stdout.trim();
if (enAvance && enAvance !== '0') fail(`${enAvance} commit(s) pas encore poussé(s) : git push d’abord.`);

// ---------------------------------------------------------------- installeur + manifeste
const b = spawnSync(process.execPath, [path.join(__dirname, 'build-installer.js')], { cwd: ROOT, stdio: 'inherit' });
if (b.status !== 0) fail('La construction de l’installeur a échoué.');
const FICHIER = `Elikya-Agents-Setup-${VERSION}.exe`;
const exe = path.join(DIST, FICHIER);
const sha256 = crypto.createHash('sha256').update(fs.readFileSync(exe)).digest('hex');
const manifeste = { version: VERSION, build: BUILD, url: `${RELEASES}download/${TAG}/${FICHIER}`, sha256, notes, publie_le: new Date().toISOString() };
const manifPath = path.join(DIST, 'agents.json');
fs.writeFileSync(manifPath, JSON.stringify(manifeste, null, 2) + '\n');
console.log(`\nManifeste : ${path.relative(ROOT, manifPath)}  (build ${BUILD}, sha256 ${sha256.slice(0, 12)}…)`);

// ---------------------------------------------------------------- publication
console.log(`Publication de ${TAG} sur GitHub…`);
try {
  gh(['release', 'create', TAG, exe, manifPath, '--repo', REPO, '--target', 'main', '--latest',
      '--title', `Elikya Agents ${VERSION}`, '--notes', notes], { stdio: 'inherit' });
} catch { fail('La création de la Release a échoué (voir le message ci-dessus).'); }
console.log(`\n✓ ${TAG} publiée. Les postes des agents proposeront la mise à jour au prochain démarrage (ou dans les 3 h).`);
