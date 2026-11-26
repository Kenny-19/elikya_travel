// Module Fourniture — pensé pour être TRÈS simple :
// - s'ouvre sur les COMMANDES : chaque commande à livrer est une carte avec un gros bouton « C'est livré » ;
// - nouvelle commande en 2 étapes (client, produits avec − / +), total calculé, alerte si le stock ne suffit pas ;
// - STOCK : liste simple, « À recommander » en haut, bouton « Compter le stock » (inventaire).
// Le stock baisse tout seul quand une commande passe « livrée » (déclencheur db/stock_auto.sql) ;
// « Compter le stock » le corrige. Disponible = stock − ce qui est réservé par les commandes « à livrer ».
// Montants en USD.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/remote.dart';
import '../../profile.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets.dart';

const categories = ['Tuyauterie', 'Sécurité/EPI', 'Informatique', 'Ménager', 'Technique', 'Autre'];
const statutsCommande = {
  'brouillon': ('Pas encore confirmée', Elk.info),
  'a_livrer': ('À livrer', Elk.warn),
  'livree': ('Livrée', Elk.ok),
  'annulee': ('Annulée', Elk.crit),
};

String _usd(Object? n) => Elk.money(n, 'USD');
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

/// Quantités réservées par produit = lignes des commandes « à livrer ».
Map<String, int> reservations(List<JsonRow> commandes, List<JsonRow> lignes) {
  final aLivrer = {
    for (final c in commandes)
      if (c['statut'] == 'a_livrer') '${c['id']}',
  };
  final out = <String, int>{};
  for (final l in lignes) {
    if (aLivrer.contains('${l['commande_id']}')) {
      out.update('${l['produit_id']}', (q) => q + _int(l['quantite']), ifAbsent: () => _int(l['quantite']));
    }
  }
  return out;
}

/// État d'un produit en mots simples : (texte, couleur).
(String, Color) etatProduit(int stock, int reserve, int seuil) {
  final dispo = stock - reserve;
  if (stock <= 0) return ('Plus rien en stock', Elk.crit);
  if (dispo < 0) return ('Pas assez pour les commandes', Elk.crit);
  if (stock <= seuil) return ('Bientôt épuisé', Elk.warn);
  return ('OK', Elk.ok);
}

class FourniturePage extends StatefulWidget {
  const FourniturePage({super.key, required this.data, required this.profile});
  final DataService data;
  final Profile profile;
  @override
  State<FourniturePage> createState() => _FourniturePageState();
}

class _FourniturePageState extends State<FourniturePage> with AutoRafraichi {
  @override
  void rafraichir() => _load(silencieux: true); // mise à jour automatique (navigation.dart)

  String vue = 'commandes';
  bool loading = true, terminees = false;
  String? error;
  List<JsonRow> produits = [], commandes = [], lignes = [], clients = [];

  DataService get data => widget.data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silencieux = false}) async {
    if (!silencieux) setState(() => loading = true);
    final r = await Future.wait([
      data.select('produits', const Query(orderBy: 'ref')),
      data.select('commandes', const Query(embed: ['clients(nom)'], orderBy: 'cree_le', ascending: false, limit: 300)),
      data.select('commande_lignes', const Query(embed: ['produits(designation)'], limit: 3000)),
      data.select('clients', const Query(orderBy: 'nom')),
    ]);
    if (!mounted) return;
    setState(() {
      produits = (r[0].data ?? []).where((p) => p['actif'] != false).toList();
      commandes = r[1].data ?? [];
      lignes = r[2].data ?? [];
      clients = r[3].data ?? [];
      error = r.map((x) => x.error).whereType<String>().firstOrNull;
      loading = false;
    });
    // bouton « Nouvelle commande » de l'accueil
    if (Navigation.prendreAction('fourniture') == 'nouvelle_commande' && clients.isNotEmpty && produits.isNotEmpty) {
      setState(() => vue = 'commandes');
      _newCommande();
    }
  }

  Future<void> _editProduit([JsonRow? p]) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _ProduitDialog(data: data, produit: p, refsExistantes: {for (final x in produits) '${x['ref']}'}),
    );
    if (res == null || !mounted) return;
    toast(context, 'Produit ${res.data?['ref'] ?? ''} enregistré${savedSuffix(res.offline)}');
    _load();
  }

  Future<void> _compter(JsonRow p) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _CompterDialog(data: data, produit: p),
    );
    if (res == null || !mounted) return;
    toast(context, 'Stock de ${p['designation']} mis à jour${savedSuffix(res.offline)}');
    _load();
  }

  Future<void> _newCommande() async {
    final res = await showDialog<(String, bool)>(
      context: context,
      builder: (_) =>
          _CommandeDialog(data: data, clients: clients, produits: produits, reserve: reservations(commandes, lignes)),
    );
    if (res == null || !mounted) return;
    toast(context, 'Commande ${res.$1} enregistrée${savedSuffix(res.$2)}');
    _load();
  }

  Future<void> _setStatut(JsonRow c, String statut) async {
    if (statut == 'annulee') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Annuler la commande ${c['ref']} ?'),
          content: const Text('Elle ne comptera plus dans les chiffres. Vous ne pourrez pas la remettre.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non, la garder')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Elk.crit, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oui, annuler'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final res = await data.update('commandes', c['id'] as Object, {'statut': statut});
    if (!mounted) return;
    toast(
      context,
      res.ok
          ? 'Commande ${c['ref']} : ${statutsCommande[statut]!.$1}${savedSuffix(res.offline)}'
          : 'Erreur : ${res.error}',
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Fourniture',
          subtitle: vue == 'commandes'
              ? 'Les commandes des clients : notez-les, puis marquez-les livrées.'
              : 'Ce qu’il reste en magasin. Le stock baisse tout seul à chaque livraison.',
          actions: [
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SegmentedButton<String>(
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontFamily: Elk.font, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          segments: const [
            ButtonSegment(value: 'commandes', label: Text('Commandes'), icon: Icon(Icons.receipt_long_outlined)),
            ButtonSegment(value: 'stock', label: Text('Stock'), icon: Icon(Icons.inventory_2_outlined)),
          ],
          selected: {vue},
          onSelectionChanged: (s) => setState(() => vue = s.first),
        ),
        const SizedBox(height: 18),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Erreur : $error', style: const TextStyle(color: Elk.crit)),
          ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (vue == 'commandes')
          ..._commandes(context)
        else
          ..._stock(context),
      ],
    );
  }

  // ---------------------------------------------------------------- commandes
  List<Widget> _commandes(BuildContext context) {
    final enCours = commandes.where((c) => c['statut'] == 'a_livrer' || c['statut'] == 'brouillon').toList();
    final finies = commandes.where((c) => c['statut'] == 'livree' || c['statut'] == 'annulee').toList();
    final peutCommander = clients.isNotEmpty && produits.isNotEmpty;
    final aLivrer = enCours.where((c) => c['statut'] == 'a_livrer');
    return [
      Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            height: 58,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                textStyle: const TextStyle(fontFamily: Elk.font, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              onPressed: peutCommander ? _newCommande : null,
              icon: const Icon(Icons.add_shopping_cart, size: 24),
              label: const Text('Nouvelle commande'),
            ),
          ),
          if (!peutCommander)
            Text(
              clients.isEmpty
                  ? 'Ajoutez d’abord un client (menu Clients).'
                  : 'Ajoutez d’abord un produit (onglet Stock).',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
        ],
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          const TitreSection('À livrer'),
          const SizedBox(width: 12),
          if (aLivrer.isNotEmpty)
            Text(
              '${aLivrer.length} commande${aLivrer.length > 1 ? 's' : ''} · '
              '${_usd(aLivrer.fold<num>(0, (s, c) => s + _num(c['total'])))}',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (enCours.isEmpty)
        const EtatVide(icone: Icons.local_shipping_outlined, texte: 'Aucune commande à livrer. Tout est à jour !')
      else
        for (final c in enCours) _carteCommande(c),
      const SizedBox(height: 14),
      if (finies.isNotEmpty)
        TextButton.icon(
          onPressed: () => setState(() => terminees = !terminees),
          icon: Icon(terminees ? Icons.expand_less : Icons.expand_more),
          label: Text(
            terminees ? 'Masquer les commandes terminées' : 'Voir les commandes terminées (${finies.length})',
          ),
        ),
      if (terminees)
        for (final c in finies)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                '${c['ref']} · ${(c['clients'] as Map?)?['nom'] ?? '—'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(_resume(c)),
              trailing: Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_usd(c['total']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Pill(statutsCommande[c['statut']]!.$1, statutsCommande[c['statut']]!.$2),
                ],
              ),
            ),
          ),
    ];
  }

  /// « 25 × Tuyau PVC Ø110, 3 × Casque » — ce qu'il faut préparer.
  String _resume(JsonRow c) => lignes
      .where((l) => '${l['commande_id']}' == '${c['id']}')
      .map((l) => '${l['quantite']} × ${(l['produits'] as Map?)?['designation'] ?? _designation(l['produit_id'])}')
      .join(', ');

  String _designation(Object? id) =>
      '${produits.where((p) => '${p['id']}' == '$id').firstOrNull?['designation'] ?? '?'}';

  Widget _carteCommande(JsonRow c) {
    final brouillon = c['statut'] == 'brouillon';
    final quand = c['cree_le'] == null
        ? ''
        : ' · notée le ${DateFormat('d MMM', 'fr_FR').format(DateTime.parse('${c['cree_le']}').toLocal())}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 20,
          runSpacing: 14,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${(c['clients'] as Map?)?['nom'] ?? 'Client'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Pill(statutsCommande[c['statut']]!.$1, statutsCommande[c['statut']]!.$2),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_resume(c), style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    '${c['ref']}$quand · total ${_usd(c['total'])}',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (brouillon)
                  FilledButton.icon(
                    onPressed: () => _setStatut(c, 'a_livrer'),
                    icon: const Icon(Icons.thumb_up_alt_outlined),
                    label: const Text('Le client confirme'),
                  )
                else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Elk.ok, foregroundColor: Colors.white),
                    onPressed: () => _setStatut(c, 'livree'),
                    icon: const Icon(Icons.check),
                    label: const Text('C’est livré'),
                  ),
                TextButton(onPressed: () => _setStatut(c, 'annulee'), child: const Text('Annuler la commande')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- stock
  List<Widget> _stock(BuildContext context) {
    final res = reservations(commandes, lignes);
    final muted = Theme.of(context).hintColor;
    (String, Color) etat(JsonRow p) => etatProduit(_int(p['stock']), res['${p['id']}'] ?? 0, _int(p['seuil_alerte']));
    final aRecommander = produits.where((p) => etat(p).$2 != Elk.ok).toList();
    return [
      if (aRecommander.isNotEmpty) ...[
        Bandeau(
          couleur: Elk.warn,
          icone: Icons.shopping_basket_outlined,
          texte: 'À recommander : ${aRecommander.length} produit${aRecommander.length > 1 ? 's' : ''}',
          details: [for (final p in aRecommander) '${p['designation']} — ${etat(p).$1.toLowerCase()}'],
        ),
        const SizedBox(height: 16),
      ],
      Row(
        children: [
          TitreSection('Produits (${produits.length})'),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => _editProduit(),
            icon: const Icon(Icons.add),
            label: const Text('Nouveau produit'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (produits.isEmpty)
        const EtatVide(
          icone: Icons.inventory_2_outlined,
          texte: 'Aucun produit. Ajoutez-en un avec « Nouveau produit ».',
        )
      else
        for (final p in produits) _carteProduit(p, res['${p['id']}'] ?? 0, etat(p), muted),
    ];
  }

  Widget _carteProduit(JsonRow p, int reserve, (String, Color) etat, Color muted) {
    final dispo = _int(p['stock']) - reserve;
    final unite = '${p['unite'] ?? ''}'.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Wrap(
          spacing: 16,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p['designation']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    '${p['ref']} · ${_usd(p['prix'])}${unite.isEmpty ? '' : ' par $unite'}'
                    '${reserve > 0 ? ' · $reserve réservé${reserve > 1 ? 's' : ''} pour des commandes' : ''}',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Disponible : $dispo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: dispo < 0 ? Elk.crit : null),
                ),
                Pill(etat.$1, etat.$2),
                OutlinedButton(onPressed: () => _compter(p), child: const Text('Compter le stock')),
                IconButton(
                  tooltip: 'Modifier le produit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editProduit(p),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ compter le stock
class _CompterDialog extends StatefulWidget {
  const _CompterDialog({required this.data, required this.produit});
  final DataService data;
  final JsonRow produit;
  @override
  State<_CompterDialog> createState() => _CompterDialogState();
}

class _CompterDialogState extends State<_CompterDialog> {
  late final _stock = TextEditingController(text: '${widget.produit['stock'] ?? 0}');
  bool busy = false;

  Future<void> _save() async {
    final v = int.tryParse(_stock.text.trim());
    if (v == null || v < 0) return toast(context, 'Indiquez un nombre entier (0 s’il n’y en a plus).');
    setState(() => busy = true);
    final res = await widget.data.update('produits', widget.produit['id'] as Object, {'stock': v});
    if (!mounted) return;
    if (!res.ok) {
      setState(() => busy = false);
      return toast(context, 'Erreur : ${res.error}');
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Compter : ${widget.produit['designation']}'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comptez ce qu’il y a vraiment en magasin, puis indiquez le nombre.',
            style: TextStyle(fontSize: 15, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _stock,
            autofocus: true,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Nombre en magasin', suffixText: '${widget.produit['unite'] ?? ''}'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer')),
    ],
  );
}

// ------------------------------------------------------------------ produit
class _ProduitDialog extends StatefulWidget {
  const _ProduitDialog({required this.data, this.produit, required this.refsExistantes});
  final DataService data;
  final JsonRow? produit; // null = création
  final Set<String> refsExistantes;
  @override
  State<_ProduitDialog> createState() => _ProduitDialogState();
}

class _ProduitDialogState extends State<_ProduitDialog> {
  final _form = GlobalKey<FormState>();
  late final p = widget.produit;
  late final _ref = TextEditingController(text: '${p?['ref'] ?? ''}');
  late final _des = TextEditingController(text: '${p?['designation'] ?? ''}');
  late final _stock = TextEditingController(text: '${p?['stock'] ?? 0}');
  late final _prix = TextEditingController(text: '${p?['prix'] ?? ''}');
  late final _seuil = TextEditingController(text: '${p?['seuil_alerte'] ?? 5}');
  late final _unite = TextEditingController(text: '${p?['unite'] ?? 'pièce'}');
  late String categorie = categories.contains(p?['categorie']) ? p!['categorie'] as String : categories.first;
  bool busy = false;

  String? _intValid(String? v) =>
      int.tryParse((v ?? '').trim()) == null || int.parse(v!.trim()) < 0 ? 'Nombre entier (0 ou plus)' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final row = {
      'designation': _des.text.trim(),
      'categorie': categorie,
      'stock': int.parse(_stock.text.trim()),
      'prix': parseAmount(_prix.text),
      'seuil_alerte': int.parse(_seuil.text.trim()),
      'unite': _unite.text.trim().isEmpty ? null : _unite.text.trim(),
    };
    final res = p == null
        ? await widget.data.insert('produits', {'ref': _ref.text.trim().toUpperCase(), ...row})
        : await widget.data.update('produits', p!['id'] as Object, row);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => busy = false);
      return toast(context, res.code == '23505' ? 'Ce code existe déjà.' : 'Erreur : ${res.error}');
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(p == null ? 'Nouveau produit' : 'Modifier ${p!['designation']}'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: formGrid([
          TextFormField(
            controller: _des,
            decoration: const InputDecoration(labelText: 'Nom du produit', hintText: 'Ex. Tuyau PVC Ø110'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Indiquez le nom du produit' : null,
          ),
          TextFormField(
            controller: _ref,
            enabled: p == null,
            decoration: const InputDecoration(labelText: 'Code produit', hintText: 'Ex. TUY-110'),
            validator: (v) {
              if (p != null) return null;
              final r = (v ?? '').trim().toUpperCase();
              if (r.isEmpty) return 'Indiquez un code court';
              return widget.refsExistantes.contains(r) ? 'Ce code existe déjà' : null;
            },
          ),
          AmountField(controller: _prix, label: 'Prix de vente (USD)', allowZero: true),
          TextFormField(
            controller: _unite,
            decoration: const InputDecoration(labelText: 'Vendu à la… (pièce, boîte)'),
          ),
          TextFormField(
            controller: _stock,
            decoration: const InputDecoration(labelText: 'Combien en magasin'),
            keyboardType: TextInputType.number,
            validator: _intValid,
          ),
          TextFormField(
            controller: _seuil,
            decoration: const InputDecoration(labelText: 'Prévenir quand il en reste'),
            keyboardType: TextInputType.number,
            validator: _intValid,
          ),
          dropdown<String>('Catégorie', categorie, {
            for (final c in categories) c: c,
          }, (v) => categorie = v ?? categorie),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer')),
    ],
  );
}

// ------------------------------------------------------------------ commande
class _Ligne {
  _Ligne(this.produit) : prix = TextEditingController(text: '${produit['prix'] ?? 0}');
  JsonRow produit;
  final qte = TextEditingController(text: '1');
  final TextEditingController prix;
  int get quantite => int.tryParse(qte.text.trim()) ?? 0;
  double get prixUnitaire => parseAmount(prix.text) ?? 0;
  double get total => quantite * prixUnitaire;
}

class _CommandeDialog extends StatefulWidget {
  const _CommandeDialog({required this.data, required this.clients, required this.produits, required this.reserve});
  final DataService data;
  final List<JsonRow> clients, produits;
  final Map<String, int> reserve;
  @override
  State<_CommandeDialog> createState() => _CommandeDialogState();
}

class _CommandeDialogState extends State<_CommandeDialog> {
  final _form = GlobalKey<FormState>();
  Object? client; // pas de client choisi d'avance : évite une commande au mauvais nom
  bool confirmee = true, busy = false;
  late final lignes = <_Ligne>[_Ligne(widget.produits.first)];

  double get total => lignes.fold(0, (s, l) => s + l.total);
  int _dispo(JsonRow p) => _int(p['stock']) - (widget.reserve['${p['id']}'] ?? 0);

  Future<void> _save() async {
    if (client == null) return toast(context, 'Choisissez le client.');
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final ref = 'CMD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final cmd = await widget.data.insert('commandes', {
      'ref': ref,
      'client_id': client,
      'statut': confirmee ? 'a_livrer' : 'brouillon',
      'total': (total * 100).round() / 100,
    });
    if (!mounted) return;
    if (!cmd.ok) {
      setState(() => busy = false);
      return toast(context, 'Erreur : ${cmd.error}');
    }
    for (final l in lignes) {
      final r = await widget.data.insert('commande_lignes', {
        'commande_id': cmd.data!['id'],
        'produit_id': l.produit['id'],
        'quantite': l.quantite,
        'prix_unitaire': l.prixUnitaire,
      });
      if (!r.ok && mounted) toast(context, 'Produit ${l.produit['designation']} non enregistré : ${r.error}');
    }
    if (mounted) Navigator.pop(context, (ref, cmd.offline));
  }

  void _plus(_Ligne l, int d) => setState(() => l.qte.text = '${(l.quantite + d).clamp(1, 999999)}');

  Widget _ligne(int i) {
    final l = lignes[i];
    final dispo = _dispo(l.produit);
    return Container(
      key: ObjectKey(l),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: dropdown<Object?>(
                  'Produit',
                  l.produit['id'],
                  {for (final p in widget.produits) p['id']: '${p['designation']}  (${_dispo(p)} disponibles)'},
                  (v) => setState(() {
                    l.produit = widget.produits.firstWhere((p) => p['id'] == v);
                    l.prix.text = '${l.produit['prix'] ?? 0}';
                  }),
                ),
              ),
              IconButton(
                tooltip: 'Retirer ce produit',
                icon: const Icon(Icons.delete_outline),
                onPressed: lignes.length == 1 ? null : () => setState(() => lignes.removeAt(i)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton.outlined(
                tooltip: 'Un de moins',
                onPressed: () => _plus(l, -1),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 96,
                child: TextFormField(
                  controller: l.qte,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(labelText: 'Quantité'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Au moins 1' : null,
                ),
              ),
              IconButton.outlined(tooltip: 'Un de plus', onPressed: () => _plus(l, 1), icon: const Icon(Icons.add)),
              const SizedBox(width: 6),
              SizedBox(
                width: 150,
                child: AmountField(controller: l.prix, label: 'Prix (USD)', allowZero: true),
              ),
              Text('= ${_usd(l.total)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          if (l.quantite > dispo)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                dispo <= 0
                    ? 'Attention : il n’y en a plus de disponible en magasin.'
                    : 'Attention : il n’en reste que $dispo de disponible.',
                style: const TextStyle(color: Elk.crit, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.add_shopping_cart, color: Elk.accentText, size: 28),
        SizedBox(width: 10),
        Text('Nouvelle commande'),
      ],
    ),
    content: SizedBox(
      width: 640,
      child: Form(
        key: _form,
        onChanged: () => setState(() {}), // total recalculé à chaque frappe
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Etape('1', 'Pour quel client ?'),
              dropdown<Object?>('Client', client, {
                for (final c in widget.clients) c['id']: '${c['nom']}',
              }, (v) => client = v),
              const SizedBox(height: 18),
              const Etape('2', 'Quels produits ?'),
              for (var i = 0; i < lignes.length; i++) _ligne(i),
              TextButton.icon(
                onPressed: () => setState(() => lignes.add(_Ligne(widget.produits.first))),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un autre produit'),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Elk.accent.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Total : ${_usd((total * 100).round() / 100)}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmee,
                onChanged: (v) => setState(() => confirmee = v),
                title: Text(
                  confirmee ? 'Le client a confirmé : à livrer' : 'Pas encore confirmée (simple devis)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer')),
    ],
  );
}
