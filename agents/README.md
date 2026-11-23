# Elikya Agents (Flutter · Windows)

Application bureau des agents. Base **en ligne Supabase prioritaire**, **SQLite local** en secours
quand Supabase est injoignable (saisies mises en file, envoyées au retour du réseau).
Architecture complète : `../docs/architecture.md`.

## Lancer
1. Supabase : `db/schema.sql` puis **`db/roles.sql`** (SQL Editor → Run).
2. Créer le compte de l'agent (Authentication → Users) avec le **même e-mail** que sa fiche `users`,
   puis relancer `db/roles.sql` (il relie les comptes par e-mail).
3. `cp lib/config.example.dart lib/config.dart` et coller la clé anon.
4. `flutter run -d windows` (dev) ou `flutter build windows --release`
   → `build/windows/x64/runner/Release/elikya_agents.exe` (dossier complet à copier sur le poste).

## Développer
- `flutter test` : logique hors ligne (faux Supabase en mémoire) + menus par rôle.
- Après modification de `lib/data/local_db.dart` : `dart run build_runner build`.
- Les écrans passent **toujours** par `DataService` (`lib/data/data_service.dart`), jamais par Supabase directement.
