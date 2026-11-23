-- =====================================================================
--  ELIKYA GESTION — Super administrateur
--  À exécuter APRÈS roles.sql (Supabase → SQL Editor → Run). Relançable sans risque.
--
--  Le super admin (un seul compte : le tien) a accès à l'entrée cachée du site direction
--  (#admin) : création des comptes agents, rôles, et saisie réactivée sur le site.
--  La sécurité est ici, côté base (RLS) et côté fonction serveur `admin-comptes` —
--  pas dans le fait que l'entrée soit « secrète ».
--
--  ⚠ AVANT DE LANCER : remplace v_email et v_nom dans le bloc tout en bas.
--    (Ne committe pas ce fichier avec ton e-mail : le dépôt GitHub est public.)
-- =====================================================================

-- 1. Rôle super administrateur : tout voir (all) + administrer (admin)
insert into roles (nom, code, permissions)
values ('Super administrateur', 'superadmin', '{"all":true,"admin":true}'::jsonb)
on conflict (nom) do update set code = excluded.code, permissions = excluded.permissions;

-- 2. Fonction de droit
create or replace function public.is_superadmin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.app_perms()->>'admin')::boolean, false)
$$;
grant execute on function public.is_superadmin() to authenticated;

-- 3. Fiches employés et rôles : lisibles par le personnel, modifiables par le SUPER ADMIN seul
--    (la direction garde la lecture ; elle ne peut plus changer les droits)
create or replace function pg_temp._pol(t text, sel text, ins text, upd text, del text)
returns void language plpgsql as $$
declare p record;
begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
    execute format('drop policy %I on %I', p.policyname, t);
  end loop;
  execute format('alter table %I enable row level security', t);
  execute format('create policy lecture on %I for select to authenticated using (%s)', t, sel);
  execute format('create policy ajout on %I for insert to authenticated with check (%s)', t, ins);
  execute format('create policy modification on %I for update to authenticated using (%s) with check (%s)', t, upd, upd);
  execute format('create policy suppression on %I for delete to authenticated using (%s)', t, del);
end $$;

select pg_temp._pol('users', 'is_staff()', 'is_superadmin()', 'is_superadmin()', 'is_superadmin()');
select pg_temp._pol('roles', 'is_staff()', 'is_superadmin()', 'is_superadmin()', 'is_superadmin()');

-- 4. Ton compte super admin
--    a) Crée d'abord ton compte : Authentication → Users → Add user (Auto Confirm), avec ton e-mail.
--    b) Renseigne v_email / v_nom ci-dessous, puis Run.
do $$
declare
  v_email text := 'TON_EMAIL@exemple.com';   -- ← ton e-mail (le même que le compte créé en a)
  v_nom   text := 'TON NOM';                 -- ← ton nom
begin
  if v_email like 'TON_EMAIL%' or position('@' in v_email) = 0 then
    raise exception 'Renseigne ton e-mail dans v_email (bloc 4 de db/superadmin.sql) avant de lancer.';
  end if;
  insert into users (nom, email, role_id, actif)
  values (v_nom, lower(v_email), (select id from roles where code = 'superadmin'), true)
  on conflict (email) do update set role_id = excluded.role_id, actif = true;
  update users u set auth_id = a.id
    from auth.users a
   where u.auth_id is null and lower(a.email) = lower(u.email);
end $$;

-- Vérification : select u.nom, u.email, r.code, u.auth_id is not null as relie
--                from users u join roles r on r.id = u.role_id where r.code = 'superadmin';
