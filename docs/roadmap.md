# Roadmap

Cible : **site web propriétaire** en JS (`web/`) + **app bureau agents** en Flutter (`agents/`),
base en ligne Supabase prioritaire, base locale en secours. Détails dans `architecture.md`.

| # | Lot | État |
|---|-----|------|
| 1 | Base Supabase (schéma + seed) | ✅ fait |
| 2 | Site : shell + Auth + module **Voyage** | ✅ fait |
| 3 | Site : module **Caisse** (sessions, mouvements, solde, clôture) | ✅ fait |
| 4 | Site : module **Mobile Money** (soldes relevés + transactions) | ✅ fait |
| 5 | Site : couche données `data.js` (IndexedDB + synchro) | ✅ fait |
| 6 | **Rôles** : `db/roles.sql` (RLS par permission + `mon_profil`), site réservé à la direction | ✅ fait |
| 7 | **App agents Flutter** : projet Windows, DataService (Supabase + SQLite drift + synchro), connexion, menu par rôle, bandeau réseau, écran **Voyage** | ✅ fait |
| 8 | App agents : **Caisse** et **Mobile Money** portés (+ tests d'écran) | ✅ fait |
| 9 | App agents : **Fourniture** (catalogue, réservé/disponible, commandes) et **Clients** (fiche, CA cumulé) | ✅ fait |
| 10 | Site : **tableau de bord** (période, variations, activité par jour, alertes, float, top clients) + **rapports** mensuels (journalier, par agent, top clients, export Excel, impression PDF) | ✅ fait |
| 10c | Site direction en **lecture seule** (consultation ; saisie dans l'app agents) | ✅ fait |
| 10d | **Super admin** : entrée cachée du site (comptes agents, rôles, saisie) — `db/superadmin.sql` + Edge Function `admin-comptes` | ✅ codé — à installer (docs/super-admin.md) |
| 10b | Site : **Fourniture** (catalogue, réservé/disponible, commandes) et **Clients** (fiches, CA cumulé) | ✅ fait |
| 11 | Mise en ligne du **site** : https://elikya0travel.netlify.app (en-têtes de sécurité vérifiés) ; code sur GitHub `Kenny-19/elikya_travel` ; mises à jour auto via `netlify.toml` | ✅ en ligne, mises à jour auto vérifiées |
| 12 | **Installeur Windows** de l'app agents (NSIS, sans droits admin, runtime VC++ inclus, données conservées) : `node scripts/build-installer.js` | ✅ fait |

## Pour ajouter un module à l'app agents
Créer `agents/lib/ui/pages/<module>_page.dart` sur le modèle de `voyage_page.dart`, l'ajouter dans
`agents/lib/ui/modules.dart` avec sa permission. Toujours passer par `DataService`.

## Pour ajouter un module au site
Dupliquer `web/js/modules/voyage.js`, changer `id/label/group`, remplir `render()`.
Toujours passer par `Elikya.data` (jamais `Elikya.db.from(...)`).

Nouvelle table Supabase → l'ajouter dans `TABLES` de `web/js/data.js` (+ `DB_VERSION`) **et** dans
`agents/lib/data/tables.dart`, puis lui donner ses politiques dans `db/roles.sql`.
