# Base de données

`schema.sql` crée les 15 tables + contraintes + index + RLS + un jeu de données de test.

## Appliquer
1. Projet Supabase → **SQL Editor** → coller `schema.sql` → **Run**.
2. Les tables apparaissent dans **Table Editor** (avec données de test).

## Points clés
- RLS activée partout, policy de départ = accès aux comptes **connectés** (à affiner par rôle).
- `users.auth_id` relie un employé à son compte **Supabase Auth**.
- Double devise (USD/CDF), paiements polymorphes (dossier/commande), caisse par session.

> Re-run : le script fait `drop table ... cascade` en tête, il repart donc propre (efface les données).
