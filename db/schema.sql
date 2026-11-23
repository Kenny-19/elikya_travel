-- =====================================================================
--  ELIKYA GESTION — Base de données (PostgreSQL / Supabase)
--  Étape conception : schéma 15 tables + contraintes + RLS + jeu de test
--  À coller dans Supabase → SQL Editor → Run.
--  Devise des montants de test : USD. Double devise gérée par la table "devises".
-- =====================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid()

-- Repartir propre (ordre inverse des dépendances) --------------------
drop table if exists audit_log, mouvements_caisse, caisse_sessions,
  paiements, momo_transactions, momo_comptes, commande_lignes, commandes,
  produits, dossiers, clients, users, roles, devises, parametres cascade;

-- =====================================================================
--  1. SYSTÈME & ACCÈS
-- =====================================================================
create table roles (
  id            serial primary key,
  nom           text not null unique,
  permissions   jsonb not null default '{}'::jsonb
);

create table users (
  id        uuid primary key default gen_random_uuid(),
  auth_id   uuid unique references auth.users(id) on delete set null, -- lien compte Supabase Auth
  nom       text not null,
  email     text unique,
  telephone text,
  role_id   int references roles(id),
  actif     boolean not null default true,
  cree_le   timestamptz not null default now()
);

-- =====================================================================
--  2. RÉFÉRENTIEL
-- =====================================================================
create table devises (
  id      serial primary key,
  code    text not null unique,         -- USD, CDF
  libelle text not null,
  taux    numeric(14,4) not null default 1,  -- taux vers devise pivot (USD = 1)
  actif   boolean not null default true
);

create table clients (
  id        uuid primary key default gen_random_uuid(),
  type      text not null default 'particulier'
              check (type in ('particulier','entreprise')),
  nom       text not null,
  telephone text,
  ville     text,
  email     text,
  segment   text,
  cree_par  uuid references users(id),
  cree_le   timestamptz not null default now()
);

create table produits (
  id           uuid primary key default gen_random_uuid(),
  ref          text not null unique,
  designation  text not null,
  categorie    text,                    -- Tuyauterie, Sécurité/EPI, Informatique, Ménager, Technique
  stock        int not null default 0,
  prix         numeric(14,2) not null default 0,
  seuil_alerte int not null default 5,
  unite        text default 'pièce',
  actif        boolean not null default true
);

-- =====================================================================
--  3. VOYAGE
-- =====================================================================
create table dossiers (
  id          uuid primary key default gen_random_uuid(),
  ref         text not null unique,
  client_id   uuid not null references clients(id),
  type        text not null
                check (type in ('billet','visa','hotel','assurance','package')),
  destination text,
  date_depart date,
  montant     numeric(14,2) not null default 0,
  devise_id   int not null references devises(id),
  statut      text not null default 'devis'
                check (statut in ('devis','confirme','paye','en_cours','annule')),
  agent_id    uuid references users(id),
  cree_le     timestamptz not null default now()
);

-- =====================================================================
--  4. FOURNITURE
-- =====================================================================
create table commandes (
  id        uuid primary key default gen_random_uuid(),
  ref       text not null unique,
  client_id uuid not null references clients(id),
  statut    text not null default 'brouillon'
              check (statut in ('brouillon','a_livrer','livree','annulee')),
  total     numeric(14,2) not null default 0,
  cree_le   timestamptz not null default now()
);

create table commande_lignes (
  id            uuid primary key default gen_random_uuid(),
  commande_id   uuid not null references commandes(id) on delete cascade,
  produit_id    uuid not null references produits(id),
  quantite      int not null check (quantite > 0),
  prix_unitaire numeric(14,2) not null
);

-- =====================================================================
--  5. MOBILE MONEY
-- =====================================================================
create table momo_comptes (
  id        serial primary key,
  operateur text not null unique check (operateur in ('airtel','orange','mpesa')),
  solde     numeric(14,2) not null default 0
);

create table momo_transactions (
  id         uuid primary key default gen_random_uuid(),
  type       text not null check (type in ('depot','retrait','transfert')),
  compte_id  int not null references momo_comptes(id),
  montant    numeric(14,2) not null,
  frais      numeric(14,2) not null default 0,
  client_tel text,
  agent_id   uuid references users(id),
  statut     text not null default 'reussi'
               check (statut in ('reussi','echec','en_attente')),
  cree_le    timestamptz not null default now()
);

-- =====================================================================
--  6. CAISSE & FINANCES
-- =====================================================================
create table caisse_sessions (
  id              uuid primary key default gen_random_uuid(),
  jour            date not null,
  solde_ouverture numeric(14,2) not null default 0,
  solde_cloture   numeric(14,2),
  agent_id        uuid references users(id),
  statut          text not null default 'ouverte'
                    check (statut in ('ouverte','cloturee')),
  unique (jour, agent_id)
);

-- Paiement = encaissement polymorphe (dossier voyage OU commande fourniture)
create table paiements (
  id          uuid primary key default gen_random_uuid(),
  source_type text not null check (source_type in ('dossier','commande')),
  source_id   uuid not null,
  mode        text not null check (mode in ('especes','mobile_money','banque')),
  montant     numeric(14,2) not null,
  devise_id   int not null references devises(id),
  recu_par    uuid references users(id),
  cree_le     timestamptz not null default now()
);

create table mouvements_caisse (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid references caisse_sessions(id),
  sens        text not null check (sens in ('entree','sortie')),
  libelle     text not null,
  module      text,                     -- Voyage, Fourniture, Mobile money, Admin...
  montant     numeric(14,2) not null,
  devise_id   int not null references devises(id),
  source_type text,                     -- paiement, depense, momo...
  source_id   uuid,
  agent_id    uuid references users(id),
  cree_le     timestamptz not null default now()
);

-- =====================================================================
--  7. TRANSVERSAL
-- =====================================================================
create table audit_log (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references users(id),
  action     text not null,            -- create, update, delete, login...
  entite     text not null,            -- dossier, paiement, produit...
  entite_id  uuid,
  details    jsonb,
  horodatage timestamptz not null default now()
);

create table parametres (
  cle    text primary key,
  valeur text,
  maj_le timestamptz not null default now()
);

-- Index utiles -------------------------------------------------------
create index idx_dossiers_client   on dossiers(client_id);
create index idx_dossiers_statut   on dossiers(statut);
create index idx_commandes_client  on commandes(client_id);
create index idx_lignes_commande   on commande_lignes(commande_id);
create index idx_momo_compte       on momo_transactions(compte_id);
create index idx_mvt_session       on mouvements_caisse(session_id);
create index idx_paiements_source  on paiements(source_type, source_id);
create index idx_audit_entite      on audit_log(entite, entite_id);

-- =====================================================================
--  JEU DE DONNÉES DE TEST (exemples — correspond à la maquette)
-- =====================================================================
insert into roles (nom, permissions) values
  ('Directeur Gérant', '{"all":true}'),
  ('Chargé de Vente & Gestion Fin.', '{"voyage":true,"caisse":true,"clients":true,"rapports":true}'),
  ('Assistant(e) Personnel(le)', '{"agenda":true,"voyage":true,"clients":true}'),
  ('Agent Mobile Money', '{"momo":true,"caisse":true}');

insert into devises (code, libelle, taux) values
  ('USD','Dollar américain', 1),
  ('CDF','Franc congolais', 2800);

insert into users (nom, email, telephone, role_id, actif) values
  ('Directeur Gérant', 'dg@elikyagroup.cd', '+243810000000', 1, true),
  ('Chargé de Vente',  'vente@elikyagroup.cd', '+243810000001', 2, true),
  ('Assistante PA',    'pa@elikyagroup.cd', '+243810000002', 3, true),
  ('Agent MoMo',       'momo@elikyagroup.cd', '+243810000003', 4, true);

insert into clients (type, nom, telephone, ville, segment, cree_par)
select 'particulier','Patrick Mwamba','+243971234567','Lubumbashi','VIP', (select id from users where role_id=2 limit 1)
union all select 'entreprise','Société Kamoa','+243819801122','Kolwezi','Grand compte',(select id from users where role_id=2 limit 1)
union all select 'particulier','Grace Ilunga','+243993345588','Likasi',null,(select id from users where role_id=3 limit 1)
union all select 'entreprise','Mine Ruashi','+243824457710','Lubumbashi','Grand compte',(select id from users where role_id=2 limit 1)
union all select 'particulier','Aline Tshibang','+243977780031','Lubumbashi',null,(select id from users where role_id=2 limit 1);

insert into produits (ref, designation, categorie, stock, prix, seuil_alerte) values
  ('TUY-110','Tuyau PVC Ø110','Tuyauterie',240,12,20),
  ('EPI-220','Casque de sécurité','Sécurité/EPI',8,15,10),
  ('INF-305','Imprimante laser','Informatique',14,180,5),
  ('MEN-410','Détergent 5 L','Ménager',60,9,15),
  ('TEC-512','Ruban adhésif isolant','Technique',5,3,10);

-- Dossiers voyage
insert into dossiers (ref, client_id, type, destination, montant, devise_id, statut, agent_id)
select 'ELK-2041', c.id, 'billet','Lubumbashi → Johannesburg', 520, d.id, 'confirme', a.id
  from clients c, devises d, users a
  where c.nom='Patrick Mwamba' and d.code='USD' and a.role_id=2;
insert into dossiers (ref, client_id, type, destination, montant, devise_id, statut, agent_id)
select 'ELK-2042', c.id, 'visa','Afrique du Sud', 180, d.id, 'en_cours', a.id
  from clients c, devises d, users a
  where c.nom='Grace Ilunga' and d.code='USD' and a.role_id=3;
insert into dossiers (ref, client_id, type, destination, montant, devise_id, statut, agent_id)
select 'ELK-2043', c.id, 'hotel','Dubaï — 3 nuits', 640, d.id, 'confirme', a.id
  from clients c, devises d, users a
  where c.nom='Société Kamoa' and d.code='USD' and a.role_id=2;

-- Mobile money
insert into momo_comptes (operateur, solde) values
  ('airtel',2310),('orange',1180),('mpesa',1820);
insert into momo_transactions (type, compte_id, montant, frais, client_tel, agent_id, statut)
select 'depot', m.id, 120, 1.2, '+243970000010', u.id, 'reussi'
  from momo_comptes m, users u where m.operateur='airtel' and u.role_id=4;
insert into momo_transactions (type, compte_id, montant, frais, client_tel, agent_id, statut)
select 'retrait', m.id, 150, 1.5, '+243970000011', u.id, 'echec'
  from momo_comptes m, users u where m.operateur='mpesa' and u.role_id=4;

-- Caisse du jour
insert into caisse_sessions (jour, solde_ouverture, agent_id, statut)
select current_date, 545, u.id, 'ouverte' from users u where u.role_id=2;

insert into mouvements_caisse (session_id, sens, libelle, module, montant, devise_id, source_type, agent_id)
select s.id,'entree','Billet ELK-2041','Voyage',520,d.id,'paiement',u.id
  from caisse_sessions s, devises d, users u where d.code='USD' and u.role_id=2 limit 1;
insert into mouvements_caisse (session_id, sens, libelle, module, montant, devise_id, source_type, agent_id)
select s.id,'sortie','Carburant','Logistique',40,d.id,'depense',u.id
  from caisse_sessions s, devises d, users u where d.code='USD' and u.role_id=2 limit 1;

-- Paramètres entreprise
insert into parametres (cle, valeur) values
  ('raison_sociale','Elikya Group'),
  ('rccm','CD/LSH/RCCM/19-B-00241'),
  ('id_nat','6-714-N45907K'),
  ('nif','A1908826Q'),
  ('siege','Croisement avenues Kasaï & Ruwe, Lubumbashi, Haut-Katanga, RDC'),
  ('devise_principale','USD'),
  ('tva','16');

-- =====================================================================
--  SÉCURITÉ (Row-Level Security)
--  Point de départ : RLS activée partout + accès réservé aux comptes
--  connectés. À RAFFINER ensuite par rôle (DG = tout, Vente = voyage/caisse…).
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'roles','users','devises','clients','produits','dossiers','commandes',
    'commande_lignes','momo_comptes','momo_transactions','caisse_sessions',
    'paiements','mouvements_caisse','audit_log','parametres']
  loop
    execute format('alter table %I enable row level security;', t);
    execute format($p$create policy "acces_authentifie" on %I
                      for all to authenticated using (true) with check (true);$p$, t);
  end loop;
end $$;

-- =====================================================================
--  FIN — base prête. Prochaine étape : API (FastAPI) + écrans.
-- =====================================================================
