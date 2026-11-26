# Elikya Agents (Flutter · Windows)

Application bureau des agents. Base **en ligne Supabase prioritaire**, **SQLite local** en secours
quand Supabase est injoignable (saisies mises en file, envoyées au retour du réseau).
Architecture complète : `../docs/architecture.md`.

## Installer sur le poste d'un agent
1. Fabriquer l'installeur (sur le poste de développement) :
   ```
   node scripts/build-installer.js
   ```
   → `dist/Elikya-Agents-Setup-<version>.exe` (~10 Mo, runtime Visual C++ inclus).
2. Copier ce fichier sur le poste de l'agent (clé USB, partage…) et **double-cliquer**.
   - Pas besoin des droits administrateur (installation pour l'utilisateur Windows courant,
     dans `%LOCALAPPDATA%\Programs\Elikya Agents`).
   - Raccourcis : bureau + menu Démarrer. Désinstallation : Paramètres → Applications.
   - Windows SmartScreen peut afficher « Windows a protégé votre ordinateur » (installeur non signé) :
     **Informations complémentaires → Exécuter quand même**.
3. Première connexion **avec internet** (compte créé par la direction, même e-mail que la fiche `users`).

### Mettre à jour — à distance (depuis la 1.6.0)
1. Augmenter `version:` dans `pubspec.yaml` : `1.6.0+8` → `1.6.1+9` (le nombre après `+` doit **toujours** augmenter).
2. `git commit` + `git push`.
3. `node scripts/publier-agents.js --notes "Ce qui change"` — construit l'installeur, calcule son empreinte
   et le publie sur GitHub (Releases) avec le manifeste `agents.json`.
   Une seule fois avant : installer l'outil GitHub (`winget install --id GitHub.cli`) puis `gh auth login`.

Sur chaque poste, l'app vérifie au démarrage puis toutes les 3 heures. Un bandeau propose
« Mettre à jour maintenant » : téléchargement, contrôle d'intégrité (SHA-256), puis l'app se ferme,
s'installe et se rouvre toute seule. Les saisies (même hors ligne) sont conservées.

Sans internet ou pour un poste neuf : installer le fichier `dist/Elikya-Agents-Setup-<version>.exe`
par-dessus (l'app doit être fermée ; l'installeur le demande). Les postes encore en 1.5.0 ou avant
doivent recevoir la 1.6.0 de cette façon une dernière fois.

### Données locales — à ne pas perdre
La base SQLite de secours (copie hors ligne + **saisies en attente**) est dans
`%APPDATA%\Elikya Group\Elikya Agents`. La désinstallation la **conserve**.
⚠ Ce chemin vient de `CompanyName` / `ProductName` de `windows/runner/Runner.rc` :
**ne pas les modifier**, sinon l'app repartirait d'une base locale vide (saisies en attente perdues).

## Développer
- Supabase : `db/schema.sql` puis `db/roles.sql`.
- `cp lib/config.example.dart lib/config.dart` et coller la clé **publishable** (jamais la secrète :
  elle serait lisible dans l'exe — `build-installer.js` la refuse).
- `flutter run -d windows` · `flutter test` · `flutter analyze`.
- Après modification de `lib/data/local_db.dart` : `dart run build_runner build`.
- Icône : `node scripts/make-icon.js` assemble `app_icon.ico` à partir du **logo officiel** (`assets/brand/mark-*.png`).
- Police **Plus Jakarta Sans** intégrée (`assets/fonts`, licence OFL) : l'app garde la charte même hors ligne.
- Les écrans passent **toujours** par `DataService` (`lib/data/data_service.dart`).
