-- =====================================================================
--  Elikya Gestion — soldes Mobile Money qui bougent tout seuls
--  À lancer APRÈS schema.sql et roles.sql (Supabase → SQL Editor → Run). Relançable sans risque.
--
--  Le solde d'un opérateur (momo_comptes.solde) = l'argent électronique chez l'opérateur (le « float »).
--  Il est ajusté automatiquement, dans la base, à chaque opération RÉUSSIE :
--     dépôt      : le client donne des billets, on lui envoie de l'argent électronique → solde − montant
--     retrait    : le client nous envoie de l'argent électronique, on lui donne des billets → solde + montant
--     transfert  : on envoie de l'argent électronique vers un autre numéro → solde − montant
--  « En attente » et « échec » ne comptent pas ; une opération en attente compte dès qu'elle passe « réussie ».
--  Les commissions (frais) ne sont pas ajoutées : l'opérateur les verse à part.
--  Le bouton « Mettre à jour le solde » de l'app reste là pour corriger d'après le téléphone de l'opérateur.
--  Les opérations déjà enregistrées AVANT ce script ne sont pas recomptées (le solde actuel est le point de départ).
-- =====================================================================

create or replace function public.momo_effet(p_type text, p_montant numeric)
returns numeric language sql immutable as $$
  select case p_type when 'retrait' then p_montant else -p_montant end
$$;

create or replace function public.momo_ajuste_solde()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- on retire l'effet de l'ancienne version (si elle comptait)…
  if tg_op in ('UPDATE','DELETE') and old.statut = 'reussi' then
    update momo_comptes set solde = solde - momo_effet(old.type, old.montant) where id = old.compte_id;
  end if;
  -- … et on ajoute celui de la nouvelle (si elle compte)
  if tg_op in ('INSERT','UPDATE') and new.statut = 'reussi' then
    update momo_comptes set solde = solde + momo_effet(new.type, new.montant) where id = new.compte_id;
  end if;
  return null;
end $$;

drop trigger if exists momo_transactions_solde on momo_transactions;
create trigger momo_transactions_solde
  after insert or update of statut, montant, type, compte_id or delete on momo_transactions
  for each row execute function public.momo_ajuste_solde();

-- vérification : doit renvoyer 1 ligne « momo_transactions_solde »
select tgname from pg_trigger where tgname = 'momo_transactions_solde';
