# Mise en ligne du site direction

Le site (`web/`) est **statique** : quelques fichiers HTML/CSS/JS, sans serveur à faire tourner.
Il suffit de les déposer chez un hébergeur gratuit. Les données restent dans Supabase,
protégées par les rôles (`db/roles.sql`).

## 0. Avant la première mise en ligne (Supabase)
1. `db/roles.sql` a été exécuté (sans lui, tout compte connecté verrait tout).
2. **Fermer les inscriptions libres** : Supabase → Authentication → Sign In / Providers → Email →
   décocher **« Allow new users to sign up »**. Seule la direction crée les comptes
   (Authentication → Users → Add user).
3. Mots de passe solides pour tous les comptes.

## 1. Préparer le dossier à déposer
```
cp web/config.example.js web/config.js      # puis coller la clé anon (Settings → API)
node scripts/build-site.js
```
→ crée `dist/site/`. Le script **refuse** une clé `service_role` / secrète, ajoute les en-têtes de
sécurité (`_headers` : CSP, anti-iframe, pas d'indexation) et `robots.txt`.

## 2. Déposer chez l'hébergeur

### Option A — Netlify (recommandé : glisser-déposer, HTTPS automatique)
1. Créer un compte sur netlify.com (gratuit).
2. Ouvrir **app.netlify.com/drop** et **glisser le dossier `dist/site`** dans la page.
3. Le site est en ligne sur une adresse `https://<nom-aléatoire>.netlify.app`.
   Site configuration → **Change site name** pour une adresse lisible (ex. `elikya-direction`).
4. Mises à jour : relancer `node scripts/build-site.js`, puis onglet **Deploys** → glisser à
   nouveau `dist/site`.

### Mises à jour automatiques via GitHub (recommandé une fois le site en ligne)
Dépôt : `https://github.com/Kenny-19/elikya_travel`. Le fichier `netlify.toml` dit à Netlify
comment construire le site ; il ne reconstruit que si `web/`, `scripts/` ou `netlify.toml` ont changé.
1. Netlify → le site → Site configuration → **Environment variables** :
   `SUPABASE_URL` = `https://dvqkstulfkwzffnzjhkj.supabase.co`, `SUPABASE_KEY` = la clé **publishable**.
2. Site configuration → Build & deploy → **Link repository** → GitHub → `elikya_travel`, branche `main`.
   (Les réglages de build viennent de `netlify.toml` : rien d'autre à remplir.)
3. Ensuite, chaque `git push` sur `main` met le site à jour en ~1 minute (onglet Deploys pour suivre).
`web/config.js` et `agents/lib/config.dart` ne sont **jamais** envoyés sur GitHub (`.gitignore`).

> **Scan de secrets Netlify** : il bloquait la construction parce que l'URL et la clé publishable
> apparaissent dans le site produit (`config.js`, CSP). C'est voulu — elles sont publiques par
> conception — donc `netlify.toml` les exclut du scan (`SECRETS_SCAN_OMIT_KEYS`), qui reste actif
> pour tout le reste. Une vraie clé secrète dans `SUPABASE_KEY` est refusée par `build-site.js`.

### Option B — Cloudflare Pages (même principe)
dash.cloudflare.com → Workers & Pages → Create → Pages → **Upload assets** → glisser `dist/site`.
Le fichier `_headers` est aussi pris en compte.

### Nom de domaine (facultatif)
Pour `direction.elikyagroup.cd` : Netlify → Domain management → Add a domain, puis chez le
gestionnaire du domaine, un enregistrement **CNAME** `direction` → `<site>.netlify.app`.

## 3. Après la mise en ligne
1. Supabase → Authentication → URL Configuration → **Site URL** = l'adresse du site
   (utilisée dans les e-mails de réinitialisation de mot de passe).
2. Vérifier :
   - connexion avec le compte de la direction → tableau de bord ;
   - connexion avec un compte agent → **refusée** (« réservé à la direction ») ;
   - adresse sans `https://` → redirigée en https (automatique chez Netlify / Cloudflare).

## Ce qui est public / protégé
- La page de connexion et le code JS sont visibles par tous : c'est normal pour un site web.
- La clé anon dans `config.js` est **publique par conception** : elle ne donne accès à rien sans
  compte connecté **et** fiche employé active (RLS).
- Les données ne sortent de Supabase que pour un compte autorisé par son rôle.
