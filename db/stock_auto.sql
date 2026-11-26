-- =====================================================================
--  Elikya Gestion — stock qui baisse tout seul à la livraison
--  À lancer APRÈS schema.sql et roles.sql (Supabase → SQL Editor → Run). Relançable sans risque.
--
--  Quand une commande passe « livrée », le stock de chaque produit de la commande baisse
--  de la quantité livrée. Si une commande livrée change à nouveau de statut (correction),
--  la quantité est remise en stock. Les commandes déjà livrées AVANT ce script ne sont pas
--  recomptées : le stock actuel est le point de départ.
--  « Compter le stock » (inventaire) reste disponible dans l'app pour corriger.
-- =====================================================================

create or replace function public.commande_ajuste_stock()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.statut = 'livree' and old.statut is distinct from 'livree' then
    update produits p set stock = p.stock - l.q
      from (select produit_id, sum(quantite) q from commande_lignes where commande_id = new.id group by produit_id) l
     where p.id = l.produit_id;
  elsif old.statut = 'livree' and new.statut is distinct from 'livree' then
    update produits p set stock = p.stock + l.q
      from (select produit_id, sum(quantite) q from commande_lignes where commande_id = new.id group by produit_id) l
     where p.id = l.produit_id;
  end if;
  return null;
end $$;

drop trigger if exists commandes_stock on commandes;
create trigger commandes_stock
  after update of statut on commandes
  for each row execute function public.commande_ajuste_stock();

-- vérification : doit renvoyer 1 ligne « commandes_stock »
select tgname from pg_trigger where tgname = 'commandes_stock';
