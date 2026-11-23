// Tables Supabase copiées en local, et leurs relations (pour refaire les jointures hors ligne).
// Même liste que TABLES dans web/js/data.js. Nouvelle table Supabase → l'ajouter ici.

class TableDef {
  const TableDef({this.key = 'id', this.ts = false, this.order, this.rels = const {}});

  /// Clé primaire.
  final String key;

  /// La table a une colonne cree_le (renseignée sur le poste à la création).
  final bool ts;

  /// Colonne de tri pour la copie de démarrage (sinon cree_le si ts).
  final String? order;

  /// alias embarqué → (table cible, clé étrangère). Ex. 'clients' → ('clients', 'client_id').
  final Map<String, (String, String)> rels;
}

const tables = <String, TableDef>{
  'roles': TableDef(),
  'devises': TableDef(),
  'users': TableDef(rels: {'roles': ('roles', 'role_id')}),
  'clients': TableDef(ts: true, rels: {'users': ('users', 'cree_par')}),
  'produits': TableDef(),
  'dossiers': TableDef(
    ts: true,
    rels: {'clients': ('clients', 'client_id'), 'devises': ('devises', 'devise_id'), 'users': ('users', 'agent_id')},
  ),
  'commandes': TableDef(ts: true, rels: {'clients': ('clients', 'client_id')}),
  'commande_lignes': TableDef(
    rels: {'produits': ('produits', 'produit_id'), 'commandes': ('commandes', 'commande_id')},
  ),
  'momo_comptes': TableDef(),
  'momo_transactions': TableDef(
    ts: true,
    rels: {'momo_comptes': ('momo_comptes', 'compte_id'), 'users': ('users', 'agent_id')},
  ),
  'caisse_sessions': TableDef(order: 'jour', rels: {'users': ('users', 'agent_id')}),
  'paiements': TableDef(ts: true, rels: {'devises': ('devises', 'devise_id'), 'users': ('users', 'recu_par')}),
  'mouvements_caisse': TableDef(
    ts: true,
    rels: {
      'devises': ('devises', 'devise_id'),
      'caisse_sessions': ('caisse_sessions', 'session_id'),
      'users': ('users', 'agent_id'),
    },
  ),
  'parametres': TableDef(key: 'cle'),
};

String keyOf(String table) => tables[table]?.key ?? 'id';
