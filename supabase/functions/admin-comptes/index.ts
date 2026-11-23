// Supabase Edge Function « admin-comptes » — gestion des comptes, réservée au SUPER ADMIN.
// Pourquoi une fonction serveur : créer un compte de connexion ou changer un mot de passe exige
// la clé service_role, qui ne doit JAMAIS être dans le site. Ici elle reste côté Supabase
// (variable SUPABASE_SERVICE_ROLE_KEY fournie automatiquement à la fonction).
//
// Déploiement : Supabase → Edge Functions → Deploy a new function → Via Editor
//   nom : admin-comptes · coller ce fichier · Deploy (laisser « Verify JWT » activé).
// Appel (site) : supabase.functions.invoke('admin-comptes', { body: { action, ... } })
//
// Actions : lister · creer {nom,email,password,role_id,telephone?} · modifier {user_id,nom?,telephone?,role_id?}
//           mot_de_passe {user_id,password} · activer {user_id,actif}
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
const erreur = (message: string, status = 400) => json({ error: message }, status);

const emailOk = (e: unknown) => typeof e === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);
const mdpOk = (p: unknown) => typeof p === 'string' && p.length >= 8;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return erreur('Méthode non autorisée', 405);

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1. Qui appelle ? (jeton de la session du site)
  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: auth, error: authErr } = await admin.auth.getUser(jwt);
  if (authErr || !auth?.user) return erreur('Session invalide : reconnecte-toi.', 401);

  // 2. Est-ce le super admin ? (fiche employé active + rôle avec permissions.admin)
  const { data: moi } = await admin
    .from('users').select('id, actif, roles(code, permissions)')
    .eq('auth_id', auth.user.id).maybeSingle();
  // deno-lint-ignore no-explicit-any
  const perms = (moi as any)?.roles?.permissions ?? {};
  if (!moi?.actif || perms.admin !== true) return erreur('Réservé au super administrateur.', 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return erreur('Requête illisible.'); }

  try {
    switch (body.action) {
      case 'lister': {
        const { data: fiches, error } = await admin
          .from('users').select('id, nom, email, telephone, actif, auth_id, role_id, cree_le, roles(nom, code)')
          .order('nom');
        if (error) return erreur(error.message, 500);
        const { data: list } = await admin.auth.admin.listUsers({ perPage: 1000 });
        const parId = new Map((list?.users ?? []).map((u) => [u.id, u]));
        return json({
          comptes: (fiches ?? []).map((f) => {
            const a = f.auth_id ? parId.get(f.auth_id) : undefined;
            return { ...f, compte: !!a, derniere_connexion: a?.last_sign_in_at ?? null };
          }),
        });
      }

      case 'creer': {
        const { nom, email, password, role_id, telephone } = body as Record<string, string>;
        if (!nom?.trim()) return erreur('Nom requis.');
        if (!emailOk(email)) return erreur('E-mail invalide.');
        if (!mdpOk(password)) return erreur('Mot de passe : 8 caractères minimum.');
        const { data: role } = await admin.from('roles').select('id, code').eq('id', role_id).maybeSingle();
        if (!role) return erreur('Rôle inconnu.');
        if (role.code === 'superadmin') return erreur('Le rôle super administrateur ne s’attribue pas depuis le site.');
        const mail = email.trim().toLowerCase();

        const { data: cree, error: e1 } = await admin.auth.admin.createUser({ email: mail, password, email_confirm: true });
        if (e1 || !cree?.user) {
          return erreur(/already|registered|exists/i.test(e1?.message ?? '') ? 'Un compte existe déjà avec cet e-mail.' : (e1?.message ?? 'Création impossible.'));
        }
        // fiche employé (créée ou reliée si elle existait déjà avec cet e-mail)
        const { data: fiche, error: e2 } = await admin.from('users')
          .upsert({ nom: nom.trim(), email: mail, telephone: telephone?.trim() || null, role_id: role.id, actif: true, auth_id: cree.user.id },
                  { onConflict: 'email' })
          .select('id').single();
        if (e2) { await admin.auth.admin.deleteUser(cree.user.id); return erreur(e2.message, 500); } // annule
        return json({ ok: true, user_id: fiche.id });
      }

      case 'modifier': {
        const { user_id, nom, telephone, role_id } = body as Record<string, string>;
        const patch: Record<string, unknown> = {};
        if (typeof nom === 'string' && nom.trim()) patch.nom = nom.trim();
        if (typeof telephone === 'string') patch.telephone = telephone.trim() || null;
        if (role_id != null) {
          const { data: role } = await admin.from('roles').select('id, code').eq('id', role_id).maybeSingle();
          if (!role) return erreur('Rôle inconnu.');
          if (role.code === 'superadmin') return erreur('Le rôle super administrateur ne s’attribue pas depuis le site.');
          if (user_id === moi.id) return erreur('Tu ne peux pas changer ton propre rôle.');
          patch.role_id = role.id;
        }
        const { error } = await admin.from('users').update(patch).eq('id', user_id);
        return error ? erreur(error.message, 500) : json({ ok: true });
      }

      case 'mot_de_passe': {
        const { user_id, password } = body as Record<string, string>;
        if (!mdpOk(password)) return erreur('Mot de passe : 8 caractères minimum.');
        const { data: f } = await admin.from('users').select('auth_id').eq('id', user_id).maybeSingle();
        if (!f?.auth_id) return erreur('Cette fiche n’a pas de compte de connexion.');
        const { error } = await admin.auth.admin.updateUserById(f.auth_id, { password });
        return error ? erreur(error.message, 500) : json({ ok: true });
      }

      case 'activer': {
        const { user_id, actif } = body as { user_id: string; actif: boolean };
        if (user_id === moi.id && !actif) return erreur('Tu ne peux pas désactiver ton propre compte.');
        const { data: f, error } = await admin.from('users').update({ actif: !!actif }).eq('id', user_id).select('auth_id').single();
        if (error) return erreur(error.message, 500);
        // compte désactivé = connexion bloquée (et la RLS ne lui montre plus rien)
        if (f?.auth_id) await admin.auth.admin.updateUserById(f.auth_id, { ban_duration: actif ? 'none' : '876000h' });
        return json({ ok: true });
      }

      default:
        return erreur('Action inconnue.');
    }
  } catch (e) {
    return erreur(e instanceof Error ? e.message : String(e), 500);
  }
});
