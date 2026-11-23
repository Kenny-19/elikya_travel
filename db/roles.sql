-- =====================================================================
--  ELIKYA GESTION — Sécurité par RÔLE (Row-Level Security)
--  À exécuter APRÈS schema.sql (Supabase → SQL Editor → Run).
--  Ne supprime AUCUNE donnée : peut être relancé sans risque.
--
--  Principe : chaque compte Supabase Auth est relié à un employé (table users),
--  qui a un rôle (table roles). Les droits viennent de roles.permissions (jsonb) :
--    {"all":true}                → Direction (propriétaire) : tout voir, tout modifier
--    {"voyage":true,"caisse":…}  → accès module par module
--  Un compte connecté SANS fiche employé active ne voit RIEN.
-- =====================================================================

-- 1. Code court par rôle (utilisé par les applications) ---------------
alter table roles add column if not exists code text unique;
update roles set code = case nom
    when 'Directeur Gérant'                 then 'dg'
    when 'Chargé de Vente & Gestion Fin.'   then 'vente'
    when 'Assistant(e) Personnel(le)'       then 'pa'
    when 'Agent Mobile Money'               then 'momo'
  end
where code is null;

-- Le chargé de vente suit aussi la fourniture (catalogue, commandes)
update roles set permissions = permissions || '{"fourniture":true}'::jsonb where code = 'vente';

-- 2. Relier les comptes Auth aux employés (par e-mail) ----------------
--    Crée d'abord le compte dans Authentication → Users avec le MÊME e-mail
--    que dans la table users, puis relance ce script (ou juste ce bloc).
update users u set auth_id = a.id
  from auth.users a
 where u.auth_id is null and lower(a.email) = lower(u.email);

-- 3. Fonctions de droits ------------------------------------------------
--    security definer : lisent users/roles sans être bloquées par la RLS.
create or replace function public.app_perms() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((
    select r.permissions
      from users u join roles r on r.id = u.role_id
     where u.actif
       and (u.auth_id = auth.uid()
            or (u.auth_id is null and lower(u.email) = lower(auth.jwt()->>'email')))
     order by (u.auth_id = auth.uid()) desc nulls last
     limit 1), '{}'::jsonb)
$$;

create or replace function public.is_dg() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.app_perms()->>'all')::boolean, false)
$$;

create or replace function public.has_perm(m text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_dg() or coalesce((public.app_perms()->>m)::boolean, false)
$$;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select public.app_perms() <> '{}'::jsonb
$$;

-- Profil du compte connecté (appelé par les applis : rpc('mon_profil'))
create or replace function public.mon_profil() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'user_id', u.id, 'nom', u.nom, 'email', u.email,
    'role', r.nom, 'role_code', r.code, 'permissions', r.permissions)
    from users u join roles r on r.id = u.role_id
   where u.actif
     and (u.auth_id = auth.uid()
          or (u.auth_id is null and lower(u.email) = lower(auth.jwt()->>'email')))
   order by (u.auth_id = auth.uid()) desc nulls last
   limit 1
$$;

grant execute on function public.app_perms(), public.is_dg(), public.has_perm(text),
  public.is_staff(), public.mon_profil() to authenticated;

-- 4. Politiques par table ----------------------------------------------
--    _pol(table, lecture, ajout, modification, suppression)
create or replace function pg_temp._pol(t text, sel text, ins text, upd text, del text)
returns void language plpgsql as $$
declare p record;
begin
  -- supprime les anciennes politiques de la table (dont "acces_authentifie")
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
    execute format('drop policy %I on %I', p.policyname, t);
  end loop;
  execute format('alter table %I enable row level security', t);
  execute format('create policy lecture on %I for select to authenticated using (%s)', t, sel);
  execute format('create policy ajout on %I for insert to authenticated with check (%s)', t, ins);
  execute format('create policy modification on %I for update to authenticated using (%s) with check (%s)', t, upd, upd);
  execute format('create policy suppression on %I for delete to authenticated using (%s)', t, del);
end $$;

-- Référentiel : lisible par tout le personnel
select pg_temp._pol('roles',      'is_staff()', 'is_dg()', 'is_dg()', 'is_dg()');
select pg_temp._pol('users',      'is_staff()', 'is_dg()', 'is_dg()', 'is_dg()');
select pg_temp._pol('devises',    'is_staff()', 'is_dg()', 'is_dg()', 'is_dg()');
select pg_temp._pol('parametres', 'is_staff()', 'is_dg()', 'is_dg()', 'is_dg()');
select pg_temp._pol('clients',    'is_staff()',
  'has_perm(''clients'') or has_perm(''voyage'') or has_perm(''fourniture'')',
  'has_perm(''clients'') or has_perm(''voyage'') or has_perm(''fourniture'')', 'is_dg()');
select pg_temp._pol('produits',   'is_staff()', 'has_perm(''fourniture'')', 'has_perm(''fourniture'')', 'is_dg()');

-- Activités : module par module
select pg_temp._pol('dossiers',          'has_perm(''voyage'')',     'has_perm(''voyage'')',     'has_perm(''voyage'')',     'is_dg()');
select pg_temp._pol('commandes',         'has_perm(''fourniture'')', 'has_perm(''fourniture'')', 'has_perm(''fourniture'')', 'is_dg()');
select pg_temp._pol('commande_lignes',   'has_perm(''fourniture'')', 'has_perm(''fourniture'')', 'has_perm(''fourniture'')', 'has_perm(''fourniture'')');
select pg_temp._pol('momo_comptes',      'has_perm(''momo'')',       'is_dg()',                  'has_perm(''momo'')',       'is_dg()');
select pg_temp._pol('momo_transactions', 'has_perm(''momo'')',       'has_perm(''momo'')',       'has_perm(''momo'')',       'is_dg()');
select pg_temp._pol('caisse_sessions',   'has_perm(''caisse'')',     'has_perm(''caisse'')',     'has_perm(''caisse'')',     'is_dg()');
select pg_temp._pol('mouvements_caisse', 'has_perm(''caisse'')',     'has_perm(''caisse'')',     'has_perm(''caisse'')',     'is_dg()');
select pg_temp._pol('paiements',         'has_perm(''caisse'')',
  'has_perm(''caisse'') or has_perm(''voyage'') or has_perm(''fourniture'')', 'has_perm(''caisse'')', 'is_dg()');

-- Journal d'audit : tout le personnel écrit, seule la direction lit
select pg_temp._pol('audit_log', 'is_dg()', 'is_staff()', 'is_dg()', 'is_dg()');

-- =====================================================================
--  Vérification rapide (à lancer connecté… ou lire simplement) :
--    select code, permissions from roles order by id;
--    select nom, email, auth_id is not null as relie from users;
-- =====================================================================
