# Elikya Gestion — guide projet (Claude Code)

Application interne de **suivi d'activité** pour **Elikya Group** (Lubumbashi, RDC) :
agence de voyage + fourniture de biens + mobile money. Multi-modules, base partagée en ligne.

> **Nature de l'app : SUIVI, pas de manipulation d'argent.** On enregistre et on consulte
> des transactions (ventes, commandes, mobile money, caisse) pour le reporting. L'app ne
> traite aucun paiement réel — c'est un **journal**. Donc : pas de logique financière atomique,
> pas de backend lourd.

## Pile technique
- **Site propriétaire** (`web/`) : HTML/CSS/JS vanilla, aucun build.
- **App agents** (`agents/`) : **Flutter** Windows desktop, base locale **SQLite (drift)**.
- **Données** : **Supabase** (PostgreSQL + Auth + RLS). Les deux applis parlent **directement** à Supabase.
- **Pas de serveur** intermédiaire (ni FastAPI).
- UI en **français**, thème **graphite + doré** (`web/assets/styles.css`, `agents/lib/ui/theme.dart`).

## Architecture (détails dans `docs/architecture.md`)
- **Propriétaire** → **site web JS** (`web/`), **réservé à la direction** : vue globale.
- **Agents** → **app bureau Flutter** (`agents/`) : saisie quotidienne, modules selon le rôle.
- **Une base en ligne Supabase = prioritaire.** L'app agents garde une **base locale SQLite**
  utilisée **seulement si Supabase est inaccessible** ; les saisies hors ligne sont mises en file
  et synchronisées au retour du réseau. La base en ligne reste la source de vérité.
```
Site propriétaire (web/, JS) ──────┐
                                   ├─HTTPS─► Supabase (PostgreSQL, Auth, RLS par rôle)
App agents (agents/, Flutter) ─────┘   ▲
   └─ SQLite drift (secours) ── synchro ┘
```
- **Rôles** : `db/roles.sql`. Droits = `roles.permissions` (`{"all":true}` = direction, sinon
  `voyage`/`caisse`/`momo`/`fourniture`/`clients`). La RLS les applique via `has_perm()`.
  Les applis lisent le profil par `rpc('mon_profil')`.

## Structure du dépôt
```
db/roles.sql            # rôles : RLS par permission + mon_profil (à lancer après schema.sql)
scripts/build-site.js   # prépare dist/site pour l'hébergeur (vérifie la clé anon, CSP) — cf. docs/mise-en-ligne.md
scripts/build-installer.js # installeur Windows de l'app agents (NSIS) → dist/Elikya-Agents-Setup-<version>.exe
scripts/make-icon.js    # génère l'icône de l'app agents (monogramme « E »)
agents/installer/       # script NSIS de l'installeur
agents/                 # app agents Flutter (voir agents/README.md)
db/schema.sql           # 15 tables + contraintes + index + RLS + jeu de test
web/index.html          # shell de l'app (login + sidebar + zone module)
web/config.example.js   # à copier en web/config.js et compléter (clé anon)
web/assets/styles.css   # design system (tokens, composants)
web/js/core.js          # registre des modules + helpers (money, pill, toast)
web/js/supabaseClient.js# init du client Supabase
web/js/data.js          # Elikya.data : en ligne prioritaire + IndexedDB secours + synchro
web/js/stats.js         # calculs tableau de bord / rapports (fonctions pures, testées : node --test web/tests/stats.test.js)
web/js/charts.js        # graphique SVG colonnes empilées (légende, info-bulle, tableau des valeurs)
web/vendor/supabase.js  # copie locale de supabase-js (hors ligne)
web/js/app.js           # boot : auth, sidebar, routage des modules
web/js/modules/*.js     # un fichier par module (tous faits : dashboard, voyage, caisse, momo, fourniture, clients, rapports)
docs/                   # architecture.md, roadmap.md
```

## Comment lancer (dev)
1. Appliquer `db/schema.sql` puis `db/roles.sql` dans Supabase (SQL Editor → Run).
2. Créer un utilisateur : Supabase → Authentication → Users → Add user (Auto Confirm), avec le
   **même e-mail** qu'une fiche `users` (ex. `dg@elikyagroup.cd` pour le site), puis relancer `db/roles.sql`.
3. `cp web/config.example.js web/config.js` puis coller la **clé anon** (Settings → API).
4. Ouvrir `web/index.html` dans Chrome, se connecter.
   (Pour les ES modules on reste en scripts classiques → marche en `file://`, sans serveur.)

## Modèle de module (convention à suivre pour en ajouter un)
Chaque module s'auto-enregistre via `Elikya.registerModule(...)` :
```js
Elikya.registerModule({
  id: 'fourniture',          // identifiant unique (= hash de route)
  label: 'Fourniture',       // libellé sidebar
  group: 'Activités',        // 'Pilotage' | 'Activités' | 'Référentiel' | 'Système'
  async render(root){        // root = élément DOM à remplir
    const store = Elikya.data; // en ligne prioritaire, secours local
    // 1) afficher un squelette  2) charger via store.select('table', {...})
    // 3) rendre tableau/cartes avec Elikya.h (money, pill, toast)
  }
});
```
`web/js/modules/voyage.js` est l'exemple de référence (KPIs, liste, création) ; `fourniture.js` montre un
formulaire à lignes multiples, `dashboard.js` / `rapports.js` les calculs (`stats.js`) et graphiques (`charts.js`).

### Correspondance modules ↔ tables
| Module       | Tables principales |
|--------------|--------------------|
| Voyage       | `dossiers`, `clients`, `devises` |
| Fourniture   | `produits`, `commandes`, `commande_lignes` |
| Mobile Money | `momo_comptes`, `momo_transactions` |
| Caisse       | `caisse_sessions`, `mouvements_caisse`, `paiements` |
| Clients      | `clients` |
| Rapports     | vues d'agrégation (à créer) |

## Conventions
- **Vanilla JS**, pas de framework, pas d'étape de build (doit tourner en `file://`).
- Textes et libellés **en français**. Montants : `Elikya.h.money(n, codeDevise)`.
- Statuts → pastilles via `Elikya.h.pill(label, kind)` (`ok|warn|crit|info|neutral`).
- Couleurs et espacements : **uniquement** via les tokens de `styles.css` (clair + sombre).
- **Suivi only** : ne pas introduire de logique de paiement/compensation d'argent.
- **Site = lecture seule** (`Elikya.readOnly`) : tout bouton / formulaire de saisie d'un module du site porte `data-ecriture` (masqué).
- **Données : toujours via `Elikya.data`** (select/insert/update), jamais `Elikya.db.from(...)` dans un module — sinon pas de mode hors ligne. Nouvelle table → l'ajouter dans `TABLES` de `web/js/data.js` et incrémenter `DB_VERSION`.

## Sécurité (important)
- `web/config.js` ne contient que la clé **anon** (publique côté client). **OK** à embarquer.
- **Ne jamais** committer/coller la clé **`service_role`** ni le mot de passe de la base.
- `.gitignore` exclut déjà `web/config.js` et `.env`.

## Roadmap
Voir `docs/roadmap.md`. Rôles ✅, app agents Flutter complète (Voyage, Caisse, Mobile Money, Fourniture, Clients) ✅. Site direction complet (tableau de bord, rapports, tous les modules) ✅. Site en ligne : https://elikya0travel.netlify.app — dépôt GitHub `Kenny-19/elikya_travel` (branche main), Netlify reconstruit via `netlify.toml` (variables SUPABASE_URL / SUPABASE_KEY). Installeur agents ✅ (`node scripts/build-installer.js` → `dist/Elikya-Agents-Setup-<version>.exe`, voir `agents/README.md`). ⚠ Ne pas changer CompanyName / ProductName dans `agents/windows/runner/Runner.rc` : ils fixent le dossier des données locales (`%APPDATA%\Elikya Group\Elikya Agents`).



## App agents Flutter (`agents/`)
- Écrans dans `agents/lib/ui/pages/`, déclarés dans `agents/lib/ui/modules.dart` avec leur permission
  (`voyage`, `caisse`, `momo`, `fourniture`, `clients`). `voyage_page.dart` / `caisse_page.dart` = modèles.
- Briques communes dans `agents/lib/ui/widgets.dart` (PageHeader, Kpi, TableCard, AmountField, dropdown, toast).
- **Données : toujours via `DataService`** (`agents/lib/data/data_service.dart`), jamais Supabase directement.
  Messages de saisie : `savedSuffix(res.offline)` ajoute « hors ligne, sera synchronisé ».
- `flutter analyze` et `flutter test` doivent passer (faux Supabase : `agents/test/fake_remote.dart`).
  Après modif de `local_db.dart` : `dart run build_runner build`.
- `agents/lib/config.dart` (clé anon) est ignoré par git ; modèle : `config.example.dart`.
- Nouvelle table → `agents/lib/data/tables.dart` **et** `web/js/data.js` **et** politiques dans `db/roles.sql`.
