-- =====================================================================
--  ELIKYA GESTION — Voyage complété : dates, détails par service, paiements
--  À exécuter APRÈS roles.sql (Supabase → SQL Editor → Run). Relançable sans risque :
--  n'efface aucune donnée (ajoute des colonnes et élargit des contrôles).
--  Suivi uniquement : on ENREGISTRE les encaissements, aucun paiement n'est traité.
-- =====================================================================

-- 1. Dossiers : dates et détails selon le service ------------------------
alter table dossiers
  add column if not exists date_retour date,          -- retour (billet) / départ de l'hôtel
  add column if not exists passager    text,          -- voyageur s'il n'est pas le client
  add column if not exists compagnie   text,          -- compagnie aérienne / assureur
  add column if not exists reference   text,          -- PNR, n° de réservation, n° de dossier visa…
  add column if not exists pays        text,          -- visa : pays demandé
  add column if not exists hotel       text,          -- nom de l'hôtel
  add column if not exists etape_visa  text,          -- visa : avancement
  add column if not exists notes       text;

alter table dossiers drop constraint if exists dossiers_etape_visa_check;
alter table dossiers add constraint dossiers_etape_visa_check
  check (etape_visa is null or etape_visa in ('a_deposer','depose','en_traitement','obtenu','refuse'));

alter table dossiers drop constraint if exists dossiers_dates_check;
alter table dossiers add constraint dossiers_dates_check
  check (date_retour is null or date_depart is null or date_retour >= date_depart);

-- Avancement du dossier, séparé du paiement (calculé depuis les encaissements).
-- 'paye' et 'en_cours' restent acceptés pour les anciens dossiers.
alter table dossiers drop constraint if exists dossiers_statut_check;
alter table dossiers add constraint dossiers_statut_check
  check (statut in ('devis','confirme','termine','annule','paye','en_cours'));

create index if not exists idx_dossiers_depart on dossiers(date_depart);

-- 2. Paiements (encaissements) ------------------------------------------
alter table paiements add column if not exists reference text;   -- n° de transaction mobile money / bancaire
alter table paiements drop constraint if exists paiements_source_type_check;
alter table paiements add constraint paiements_source_type_check
  check (source_type in ('dossier','commande','location'));

-- Droits : quiconque gère un module peut voir et enregistrer les encaissements de ce module.
-- (Avant : seule la caisse pouvait les lire.) Correction / suppression : direction seule.
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

select pg_temp._pol('paiements',
  'has_perm(''caisse'') or has_perm(''voyage'') or has_perm(''fourniture'') or has_perm(''location'')',
  'has_perm(''caisse'') or has_perm(''voyage'') or has_perm(''fourniture'') or has_perm(''location'')',
  'is_dg()', 'is_dg()');
