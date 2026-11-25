// Module Fourniture : catalogue (stock, alertes) + commandes clients (lignes, total, statut).
// Suivi uniquement. Le stock est un RELEVÉ (inventaire saisi à la main) : il n'est pas
// décrémenté automatiquement à la livraison — on affiche à côté ce qui est réservé par les
// commandes « à livrer », et donc le disponible. Montants en USD.
import 'package:flutter/material.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/remote.dart';
import '../../profile.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets.dart';

const categories = ['Tuyauterie', 'Sécurité/EPI', 'Informatique', 'Ménager', 'Technique', 'Autre'];
const statutsCommande = {
  'brouillon': ('Brouillon', Elk.info),
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

class FourniturePage extends StatefulWidget {
  const FourniturePage({super.key, required this.data, required this.profile});
  final DataService data;
  final Profile profile;
  @override
  State<FourniturePage> createState() => _FourniturePageState();
}

class _FourniturePageState extends State<FourniturePage> {
  String vue = 'catalogue';
  bool loading = true;
  String? error;
  List<JsonRow> produits = [], commandes = [], lignes = [], clients = [];

  DataService get data => widget.data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
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
    if (Navigation.prendreAction('fourniture') == 'nouvelle_commande' && clients.isNotEmpty && produits.isNotEmpty) {
      setState(() => vue = 'commandes');
      _newCommande();
    } // bouton de l'accueil
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

  Future<void> _newCommande() async {
    final res = await showDialog<(String, bool)>(
      context: context,
      builder: (_) => _CommandeDialog(data: data, clients: clients, produits: produits),
    );
    if (res == null || !mounted) return;
    toast(context, 'Commande ${res.$1} enregistrée${savedSuffix(res.$2)}');
    _load();
  }

  Future<void> _setStatut(JsonRow c, String statut) async {
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
          subtitle: 'Catalogue et commandes clients. Stock = inventaire relevé ; montants en USD.',
          actions: [
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
            if (vue == 'catalogue')
              FilledButton.icon(
                onPressed: loading ? null : () => _editProduit(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau produit'),
              )
            else
              FilledButton.icon(
                onPressed: loading || clients.isEmpty || produits.isEmpty ? null : _newCommande,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouvelle commande'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'catalogue', label: Text('Catalogue'), icon: Icon(Icons.inventory_2_outlined)),
            ButtonSegment(value: 'commandes', label: Text('Commandes'), icon: Icon(Icons.receipt_long_outlined)),
          ],
          selected: {vue},
          onSelectionChanged: (s) => setState(() => vue = s.first),
        ),
        const SizedBox(height: 16),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Erreur : $error', style: const TextStyle(color: Elk.crit)),
          ),
        if (vue == 'catalogue') ..._catalogue(context) else ..._commandes(context),
      ],
    );
  }

  List<Widget> _catalogue(BuildContext context) {
    final res = reservations(commandes, lignes);
    num valeur = 0;
    var alertes = 0, ruptures = 0;
    for (final p in produits) {
      valeur += _int(p['stock']) * _num(p['prix']);
      if (_int(p['stock']) <= 0) {
        ruptures++;
      } else if (_int(p['stock']) <= _int(p['seuil_alerte'])) {
        alertes++;
      }
    }
    return [
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          Kpi('Produits', '${produits.length}'),
          Kpi('Valeur du stock', _usd(valeur)),
          Kpi('Sous le seuil', '$alertes'),
          Kpi('Ruptures', '$ruptures'),
        ],
      ),
      const SizedBox(height: 16),
      TableCard(
        loading: loading,
        empty: 'Aucun produit. Clique « Nouveau produit ».',
        columns: const [
          DataColumn(label: Text('Réf.')),
          DataColumn(label: Text('Désignation')),
          DataColumn(label: Text('Catégorie')),
          DataColumn(label: Text('Stock'), numeric: true),
          DataColumn(label: Text('Réservé'), numeric: true),
          DataColumn(label: Text('Disponible'), numeric: true),
          DataColumn(label: Text('Prix'), numeric: true),
          DataColumn(label: Text('État')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final p in produits)
            () {
              final stock = _int(p['stock']), reserve = res['${p['id']}'] ?? 0, dispo = stock - reserve;
              final (etat, color) = stock <= 0
                  ? ('Rupture', Elk.crit)
                  : dispo < 0
                  ? ('Insuffisant', Elk.crit)
                  : stock <= _int(p['seuil_alerte'])
                  ? ('Sous le seuil', Elk.warn)
                  : ('OK', Elk.ok);
              return DataRow(
                cells: [
                  DataCell(Text('${p['ref']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text('${p['designation']}')),
                  DataCell(Text('${p['categorie'] ?? '—'}')),
                  DataCell(Text('$stock ${p['unite'] ?? ''}'.trim())),
                  DataCell(Text(reserve == 0 ? '—' : '$reserve')),
                  DataCell(Text('$dispo', style: TextStyle(color: dispo < 0 ? Elk.crit : null))),
                  DataCell(Text(_usd(p['prix']))),
                  DataCell(Pill(etat, color)),
                  DataCell(
                    IconButton(
                      tooltip: 'Modifier / inventaire',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _editProduit(p),
                    ),
                  ),
                ],
              );
            }(),
        ],
      ),
    ];
  }

  List<Widget> _commandes(BuildContext context) {
    final nbLignes = <String, int>{};
    for (final l in lignes) {
      nbLignes.update('${l['commande_id']}', (n) => n + 1, ifAbsent: () => 1);
    }
    final actives = commandes.where((c) => c['statut'] != 'annulee');
    final aLivrer = commandes.where((c) => c['statut'] == 'a_livrer');
    return [
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          Kpi('Commandes', '${commandes.length}'),
          Kpi('À livrer', '${aLivrer.length}'),
          Kpi('Montant à livrer', _usd(aLivrer.fold<num>(0, (s, c) => s + _num(c['total'])))),
          Kpi('Total (hors annulées)', _usd(actives.fold<num>(0, (s, c) => s + _num(c['total'])))),
        ],
      ),
      const SizedBox(height: 16),
      TableCard(
        loading: loading,
        empty: 'Aucune commande. Clique « Nouvelle commande ».',
        columns: const [
          DataColumn(label: Text('Réf.')),
          DataColumn(label: Text('Client')),
          DataColumn(label: Text('Lignes'), numeric: true),
          DataColumn(label: Text('Total'), numeric: true),
          DataColumn(label: Text('Statut')),
        ],
        rows: [
          for (final c in commandes)
            DataRow(
              cells: [
                DataCell(Text('${c['ref']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('${(c['clients'] as Map?)?['nom'] ?? '—'}')),
                DataCell(Text('${nbLignes['${c['id']}'] ?? 0}')),
                DataCell(Text(_usd(c['total']))),
                DataCell(
                  c['statut'] == 'livree' || c['statut'] == 'annulee'
                      ? Pill(statutsCommande[c['statut']]!.$1, statutsCommande[c['statut']]!.$2)
                      // brouillon / à livrer : le statut se change directement dans la liste
                      : DropdownButton<String>(
                          key: ValueKey('statut-${c['id']}'),
                          value: '${c['statut']}',
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final e in statutsCommande.entries)
                              DropdownMenuItem(value: e.key, child: Pill(e.value.$1, e.value.$2)),
                          ],
                          onChanged: (v) => v == null || v == c['statut'] ? null : _setStatut(c, v),
                        ),
                ),
              ],
            ),
        ],
      ),
    ];
  }
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
      int.tryParse((v ?? '').trim()) == null || int.parse(v!.trim()) < 0 ? 'Nombre entier ≥ 0' : null;

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
      return toast(context, res.code == '23505' ? 'Cette référence existe déjà.' : 'Erreur : ${res.error}');
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(p == null ? 'Nouveau produit' : 'Modifier ${p!['ref']} · inventaire'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: formGrid([
          TextFormField(
            controller: _ref,
            enabled: p == null,
            decoration: const InputDecoration(labelText: 'Référence', hintText: 'Ex. TUY-110'),
            validator: (v) {
              if (p != null) return null;
              final r = (v ?? '').trim().toUpperCase();
              if (r.isEmpty) return 'Référence requise';
              return widget.refsExistantes.contains(r) ? 'Cette référence existe déjà' : null;
            },
          ),
          TextFormField(
            controller: _des,
            decoration: const InputDecoration(labelText: 'Désignation'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Désignation requise' : null,
          ),
          dropdown<String>('Catégorie', categorie, {
            for (final c in categories) c: c,
          }, (v) => categorie = v ?? categorie),
          TextFormField(
            controller: _unite,
            decoration: const InputDecoration(labelText: 'Unité'),
          ),
          TextFormField(
            controller: _stock,
            decoration: const InputDecoration(labelText: 'Stock relevé'),
            keyboardType: TextInputType.number,
            validator: _intValid,
          ),
          TextFormField(
            controller: _seuil,
            decoration: const InputDecoration(labelText: 'Seuil d’alerte'),
            keyboardType: TextInputType.number,
            validator: _intValid,
          ),
          AmountField(controller: _prix, label: 'Prix unitaire (USD)', allowZero: true),
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
  const _CommandeDialog({required this.data, required this.clients, required this.produits});
  final DataService data;
  final List<JsonRow> clients, produits;
  @override
  State<_CommandeDialog> createState() => _CommandeDialogState();
}

class _CommandeDialogState extends State<_CommandeDialog> {
  final _form = GlobalKey<FormState>();
  late Object? client = widget.clients.first['id'];
  String statut = 'a_livrer';
  late final lignes = <_Ligne>[_Ligne(widget.produits.first)];
  bool busy = false;

  double get total => lignes.fold(0, (s, l) => s + l.total);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final ref = 'CMD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final cmd = await widget.data.insert('commandes', {
      'ref': ref,
      'client_id': client,
      'statut': statut,
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
      if (!r.ok && mounted) toast(context, 'Ligne ${l.produit['ref']} non enregistrée : ${r.error}');
    }
    if (mounted) Navigator.pop(context, (ref, cmd.offline));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouvelle commande'),
    content: SizedBox(
      width: 760,
      child: Form(
        key: _form,
        onChanged: () => setState(() {}), // total recalculé à chaque frappe
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              formGrid([
                dropdown<Object?>('Client', client, {
                  for (final c in widget.clients) c['id']: '${c['nom']}',
                }, (v) => client = v),
                dropdown<String>('Statut', statut, {
                  for (final e in statutsCommande.entries.where((e) => e.key != 'livree' && e.key != 'annulee'))
                    e.key: e.value.$1,
                }, (v) => statut = v ?? statut),
              ]),
              const SizedBox(height: 18),
              const Text('Lignes', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (var i = 0; i < lignes.length; i++)
                Padding(
                  key: ObjectKey(lignes[i]),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: dropdown<Object?>(
                          'Produit',
                          lignes[i].produit['id'],
                          {for (final p in widget.produits) p['id']: '${p['ref']} · ${p['designation']}'},
                          (v) => setState(() {
                            lignes[i].produit = widget.produits.firstWhere((p) => p['id'] == v);
                            lignes[i].prix.text = '${lignes[i].produit['prix'] ?? 0}';
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: lignes[i].qte,
                          decoration: const InputDecoration(labelText: 'Quantité'),
                          keyboardType: TextInputType.number,
                          validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Quantité > 0' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: AmountField(controller: lignes[i].prix, label: 'Prix unit.', allowZero: true),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(width: 110, child: Text(_usd(lignes[i].total), textAlign: TextAlign.right)),
                      IconButton(
                        tooltip: 'Retirer la ligne',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: lignes.length == 1 ? null : () => setState(() => lignes.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => lignes.add(_Ligne(widget.produits.first))),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter une ligne'),
                  ),
                  const Spacer(),
                  Text(
                    'Total : ${_usd((total * 100).round() / 100)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
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
