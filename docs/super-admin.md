# Super administrateur — entrée cachée du site direction

Un seul compte (le tien) est **super administrateur**. Sur le site direction, il a en plus :
- l'écran **Administration** (entrée cachée) :
  - **Comptes** : créer le compte d'un agent (e-mail + mot de passe généré + rôle), changer son
    rôle, réinitialiser son mot de passe, désactiver / réactiver un compte ;
  - **Rôles** : cocher les modules visibles par chaque rôle (voyage, caisse, mobile money,
    fourniture, clients) ;
- la **saisie réactivée** sur tous les modules du site (la propriétaire reste en lecture seule).

## Ouvrir l'entrée cachée
Connecté avec ton compte super admin, au choix :
- **Ctrl + Maj + A** ;
- **5 clics rapides** sur le logo en haut de la barre latérale ;
- l'adresse `https://elikya0travel.netlify.app/#admin`.

Pour tout autre compte, rien ne se passe (retour au tableau de bord).
Un petit badge orange « Super admin » sous ton nom rappelle que tu es dans ce mode.

## Sécurité (ce qui protège vraiment)
L'entrée est seulement *cachée* ; la protection est ailleurs :
- **Base (RLS, `db/superadmin.sql`)** : seules les sessions super admin peuvent modifier les
  tables `users` et `roles` (la direction les lit, mais ne peut plus changer les droits).
- **Fonction serveur `admin-comptes`** : elle vérifie à chaque appel que la session est celle
  d'une fiche active avec la permission `admin`, sinon « Réservé au super administrateur ».
  La clé secrète Supabase reste dans la fonction, **jamais** dans le site.
- Le rôle super admin ne peut pas être attribué depuis le site ; tu ne peux pas désactiver
  ni rétrograder ton propre compte (pour ne pas t'enfermer dehors).

## Mise en place (une fois)
1. **Ton compte** : Supabase → Authentication → Users → **Add user** (Auto Confirm) avec ton e-mail.
2. **`db/superadmin.sql`** : ouvre-le dans le SQL Editor, remplace `TON_EMAIL@exemple.com` et
   `TON NOM` dans le dernier bloc, puis **Run**. (Ne renvoie pas ce fichier modifié sur GitHub :
   le dépôt est public.)
3. **Fonction serveur** : Supabase → **Edge Functions** → *Deploy a new function* → *Via Editor* :
   - nom : **`admin-comptes`** (exactement) ;
   - coller le contenu de `supabase/functions/admin-comptes/index.ts` ;
   - **Deploy** (laisser « Verify JWT » activé).
   Les variables `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` sont fournies automatiquement.
4. Recharge le site, connecte-toi avec ton compte → Ctrl + Maj + A.

## Créer le compte d'un agent
Administration → Comptes → **Nouveau compte** : nom, e-mail, téléphone, rôle. Un mot de passe est
proposé (bouton ⟳ pour en générer un autre). Après « Créer le compte », les identifiants s'affichent
**une seule fois** : transmets-les à l'agent (bouton Copier). L'agent se connecte ensuite à
l'application bureau Elikya Agents (première connexion avec internet).

Les fiches du jeu de départ « Sans compte » (ex. `vente@elikyagroup.cd`) se relient en créant un
compte avec **le même e-mail**.
