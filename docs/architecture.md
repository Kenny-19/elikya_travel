# Architecture

Deux applications, **une seule base en ligne** (Supabase) qui fait foi.

```
  Propriétaire ──HTTPS──►  SITE WEB  (web/ — HTML/CSS/JS vanilla)      ─┐
  (navigateur)             réservé à la direction : vue globale,         │
                           tableau de bord, rapports, tous les modules   │
                                                                         ▼
                                                           ┌──────────────────────┐
                                                           │  Supabase (EN LIGNE) │
                                                           │  PostgreSQL + Auth   │
                                                           │  + RLS par rôle      │
                                                           │  = PRIORITAIRE       │
                                                           └──────────────────────┘
                                                                         ▲
  Agents ──────────────►  APP BUREAU (agents/ — Flutter Windows)        ─┘ synchro au
  (poste de travail)       saisie : voyage, caisse, mobile money…          retour du réseau
                           + SQLite LOCAL (drift) = secours
```

| | Propriétaire | Agents |
|---|---|---|
| Dossier | `web/` | `agents/` |
| Techno | HTML/CSS/JS vanilla | **Flutter** (Windows desktop) |
| Accès | Rôle direction uniquement (`permissions.all`) | Tout employé actif, modules selon son rôle |
| Base | En ligne (IndexedDB en secours, cf. `web/js/data.js`) | En ligne **prioritaire**, **SQLite local** en secours |

## Rôles (`db/roles.sql`)
- Chaque compte Supabase Auth est relié à une fiche `users` (par `auth_id`, ou à défaut par e-mail).
- Les droits viennent de `roles.permissions` (jsonb) : `{"all":true}` = direction ;
  sinon module par module (`voyage`, `caisse`, `momo`, `fourniture`, `clients`).
- **La base applique les droits elle-même (RLS)** via `has_perm('module')` : même si une appli
  se trompe, un agent Mobile Money ne peut ni lire ni écrire les dossiers voyage.
- Les applis lisent le profil via `rpc('mon_profil')` → nom, rôle, permissions, `user_id`
  (utilisé comme `agent_id` des saisies).
- Compte connecté **sans fiche employé active** → ne voit rien, les applis refusent l'accès.

| Rôle (code) | Permissions |
|---|---|
| Directeur Gérant (`dg`) | tout |
| Chargé de Vente & Gestion Fin. (`vente`) | voyage, caisse, clients, fourniture, rapports |
| Assistant(e) Personnel(le) (`pa`) | voyage, clients, agenda |
| Agent Mobile Money (`momo`) | momo, caisse |

## Règle de données : en ligne prioritaire, local en secours
1. **Réseau OK** → lecture/écriture directe dans Supabase. Chaque lecture réussie met à jour la copie locale.
2. **Supabase injoignable** (erreur réseau ou pas de réponse en 8 s) → **mode hors ligne** (bandeau) :
   lectures depuis la copie locale (jointures refaites en local), écritures mises en **file d'attente**.
3. **Réseau revenu** (test toutes les 15 s) → file rejouée dans l'ordre, puis l'écran se recharge.
   La base en ligne reste la **source de vérité**.

- Identifiants (UUID) et `cree_le` générés **sur le poste** → un envoi répété ne crée pas de doublon (upsert).
- Modifications (clôture, statut, relevé de solde) : **le dernier envoi gagne**.
- Saisie refusée à la synchro (ex. doublon de session de caisse) → liste « refusées » (bandeau → Voir).
- Hors ligne, il faut s'être **connecté une fois** sur le poste (session + profil mémorisés).

## App agents — `agents/` (Flutter)
```
lib/main.dart              démarrage (config, Supabase, base locale)
lib/config.dart            URL + clé anon (copie de config.example.dart, ignoré par git)
lib/data/remote.dart       accès Supabase (Remote) + erreurs réseau / métier
lib/data/local_db.dart     SQLite (drift) : copie JSON des lignes, file d'attente, refusées
lib/data/tables.dart       tables copiées + relations (même liste que web/js/data.js)
lib/data/data_service.dart DataService : select / insert / update / sync / warmup
lib/profile.dart           profil + Profile.can(module)
lib/ui/auth_gate.dart      connexion + contrôle du rôle (mon_profil, cache hors ligne)
lib/ui/shell.dart          barre latérale (modules autorisés) + bandeau réseau
lib/ui/modules.dart        registre des modules (id, libellé, permission, écran)
lib/ui/widgets.dart        briques communes (en-tête, KPI, tableau, champ montant…)
lib/ui/pages/              un écran par module (voyage, caisse, momo, fourniture, clients)
test/                      tests de la logique hors ligne + des rôles
```
- Base locale : les lignes sont stockées en JSON par (table, id) → aucun second schéma à tenir
  à jour ; une colonne ajoutée dans Supabase est copiée automatiquement.
- Après modification de `local_db.dart` : `dart run build_runner build`.

## Site propriétaire — `web/`
- Réservé à la direction : `app.js` appelle `mon_profil` et refuse les autres rôles.
- Reste en vanilla JS, aucun build. À héberger (Netlify, Vercel…) pour un accès par internet.

## Choix de suivi (app agents)
- **Stock** = inventaire **relevé** (saisi). Il n'est pas décrémenté automatiquement à la livraison
  (éviterait des écrasements entre postes hors ligne). L'écran montre le **réservé** (lignes des
  commandes « à livrer ») et le **disponible** = stock − réservé.
- **CA client** = dossiers voyage + commandes fourniture, hors annulés, en USD (CDF ÷ taux).
  Un rôle sans accès à un module voit un CA partiel, signalé à l'écran.

## Tableau de bord & rapports (site direction)
- Agrégats calculés **dans le navigateur** (`web/js/stats.js`, fonctions pures testées avec
  `node --test web/tests/stats.test.js`) à partir des tables, filtrées par date côté Supabase.
  Volumes actuels modestes → pas besoin de vues SQL ; à créer (avec `security_invoker`) si les
  temps de chargement augmentent.
- Graphiques : `web/js/charts.js` (SVG, sans dépendance). Palette validée (skill dataviz) :
  bleu / orange / vert d'eau, clair et sombre (`--series-1..3` dans `styles.css`), légende +
  info-bulle + tableau des valeurs pour chaque graphique.
- Rapports : export CSV pour Excel (« ; », BOM UTF-8) et impression / PDF via le navigateur.

## Site direction en lecture seule
- Le site sert à **consulter** l'activité : `app.js` met `Elikya.readOnly = true`.
- Les contrôles de saisie portent l'attribut `data-ecriture` → masqués par `styles.css`
  (`body.lecture-seule [data-ecriture]`). Les statuts modifiables en liste deviennent des pastilles.
- Filet de sécurité : `Elikya.data.insert/update` refusent toute écriture en lecture seule.
- Les saisies se font dans l'app agents (Flutter). Pour réactiver la saisie sur le site : `readOnly = false`.
- Nouveau module du site : marquer tout bouton / formulaire de saisie avec `data-ecriture`.
