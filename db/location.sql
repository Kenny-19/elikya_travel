-- =====================================================================
--  ELIKYA GESTION — Location de véhicules (avec ou sans chauffeur)
--  À exécuter APRÈS roles.sql (Supabase → SQL Editor → Run). Relançable sans risque :
--  ne supprime aucune donnée.
--  Suivi uniquement : on enregistre les véhicules et les locations ; aucun paiement traité.
-- =====================================================================

create extension if not exists btree_gist;   -- pour interdire les chevauchements de dates

-- 1. Parc de véhicules ---------------------------------------------------
create table if not exists vehicules (
  id                   uuid primary key default gen_random_uuid(),
  immatriculation      text not null unique,
  marque               text not null,
  modele               text,
  places               int  not null default 5 check (places > 0),
  carburant            text,                         -- Essence, Diesel…
  tarif_jour           numeric(14,2) not null default 0 check (tarif_jour >= 0),          -- USD, véhicule seul
  tarif_chauffeur_jour numeric(14,2) not null default 0 check (tarif_chauffeur_jour >= 0), -- USD, supplément chauffeur
  statut               text not null default 'disponible'
                         check (statut in ('disponible','entretien','hors_service')),     -- « loué » se déduit des locations
  notes                text,
  actif                boolean not null default true,
  cree_le              timestamptz not null default now()
);

-- 2. Locations -----------------------------------------------------------
create table if not exists locations (
  id             uuid primary key default gen_random_uuid(),
  ref            text not null unique,
  client_id      uuid not null references clients(id),
  vehicule_id    uuid not null references vehicules(id),
  date_debut     date not null,
  date_fin       date not null,
  avec_chauffeur boolean not null default false,
  chauffeur      text,                                -- nom du chauffeur si avec chauffeur
  montant        numeric(14,2) not null default 0 check (montant >= 0),
  devise_id      int  not null references devises(id),
  caution        numeric(14,2) not null default 0 check (caution >= 0),
  statut         text not null default 'reservee'
                   check (statut in ('reservee','en_cours','terminee','annulee')),
  notes          text,
  agent_id       uuid references users(id),
  cree_le        timestamptz not null default now(),
  constraint locations_dates check (date_fin >= date_debut)
);
create index if not exists idx_locations_vehicule on locations(vehicule_id);
create index if not exists idx_locations_client   on locations(client_id);
create index if not exists idx_locations_dates    on locations(date_debut, date_fin);

-- Un véhicule ne peut pas avoir deux locations actives (réservée / en cours) qui se chevauchent.
-- Vérifié par la base elle-même : même avec plusieurs postes ou une saisie faite hors ligne
-- (la synchro est alors refusée et apparaît dans « saisies refusées »).
do $$ begin
  alter table locations add constraint locations_sans_chevauchement
    exclude using gist (vehicule_id with =, daterange(date_debut, date_fin, '[]') with &&)
    where (statut in ('reservee','en_cours'));
exception when duplicate_object then null; end $$;

-- 3. Droits : nouveau module « location » ------------------------------
--    Le chargé de vente le reçoit par défaut (modifiable ensuite dans Administration → Rôles).
update roles set permissions = permissions || '{"location":true}'::jsonb where code = 'vente';

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

select pg_temp._pol('vehicules', 'has_perm(''location'')', 'has_perm(''location'')', 'has_perm(''location'')', 'is_dg()');
select pg_temp._pol('locations', 'has_perm(''location'')', 'has_perm(''location'')', 'has_perm(''location'')', 'is_dg()');

-- Vérification : select code, permissions from roles order by id;
