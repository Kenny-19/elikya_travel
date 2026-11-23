# Elikya Gestion

Application interne de **suivi d'activité** d'Elikya Group (Lubumbashi, RDC) :
voyage, fourniture et mobile money. Front vanilla + **Supabase**. Multi-modules.

> Projet pensé pour être continué avec **Claude Code** : lis `CLAUDE.md` en premier.

## Démarrage rapide
1. **Base** : Supabase → SQL Editor → `db/schema.sql` → **Run**, puis `db/roles.sql` → **Run**.
2. **Compte** : Authentication → Users → **Add user** (*Auto Confirm*) avec l'e-mail d'une fiche `users`
   (ex. `dg@elikyagroup.cd` pour le site), puis relance `db/roles.sql` pour relier le compte.
3. **Config** : `cp web/config.example.js web/config.js`, puis colle ta **clé anon**
   (Supabase → Settings → API). L'URL est déjà renseignée.
4. **Lancer** : ouvre `web/index.html` dans Chrome, connecte-toi.
   → tu vois les dossiers de test et tu peux en créer.

## Structure
```
CLAUDE.md               Guide pour Claude Code (archi, conventions, roadmap)
db/schema.sql           Base PostgreSQL (15 tables + RLS + jeu de test)
db/roles.sql            Rôles : RLS par permission (après schema.sql)
agents/                 App bureau des AGENTS (Flutter Windows, SQLite en secours, cf. agents/README.md)
web/                    Site PROPRIÉTAIRE (JS, réservé à la direction)
  index.html            Shell : login + sidebar + zone module
  assets/styles.css     Design system (thème graphite & doré, clair/sombre)
  js/core.js            Registre de modules + helpers
  js/supabaseClient.js  Init client Supabase
  js/app.js             Boot : auth, sidebar, routage
  js/modules/           Un fichier par module (tableau de bord, rapports, voyage, caisse, momo, fourniture, clients)
docs/                   architecture.md, roadmap.md
```

## État
- ✅ Base de données + sécurité RLS
- ✅ Connexion + module **Voyage** (liste + création en direct)
- ✅ Module **Caisse** (sessions, mouvements, solde théorique, clôture avec écart)
- ✅ Module **Mobile Money** (soldes relevés par opérateur, journal filtrable, statuts)
- ✅ Site : modules Fourniture et Clients
- ✅ Rôles (db/roles.sql) · site réservé à la direction
- ✅ App agents Flutter : connexion, menu par rôle, hors ligne SQLite, Voyage, Caisse, Mobile Money, Fourniture, Clients
- ✅ Site : tableau de bord + rapports mensuels (export Excel, impression PDF)
- 🟡 Mise en ligne du site : prêt (`node scripts/build-site.js`, voir `docs/mise-en-ligne.md`) · ⬜ installeur Windows de l'app agents

## Sécurité
`web/config.js` (clé anon, publique) est **ignoré par git**. Ne committe jamais la clé
`service_role` ni le mot de passe de la base.

## Versionner avec GitHub Desktop
Ouvre ce dossier comme dépôt (Add → Create/Add repository), commit initial, puis push.
Le `.gitignore` protège déjà `config.js` et `.env`.
