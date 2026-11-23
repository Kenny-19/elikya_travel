// Module Mobile Money — équivalent de web/js/modules/momo.js.
// Soldes RELEVÉS par opérateur (saisis à la main, pas recalculés) + journal des transactions.
// Suivi uniquement : aucune opération réelle. Montants en USD.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/remote.dart';
import '../../profile.dart';
import '../theme.dart';
import '../widgets.dart';

const _ops = {'airtel': 'Airtel Money', 'orange': 'Orange Money', 'mpesa': 'M-Pesa'};
const _types = {'depot': 'Dépôt', 'retrait': 'Retrait', 'transfert': 'Transfert'};
const _statuts = {'reussi': ('Réussi', Elk.ok), 'en_attente': ('En attente', Elk.warn), 'echec': ('Échec', Elk.crit)};
const _periodes = {'jour': "Aujourd'hui", 'semaine': '7 jours', 'mois': '30 jours', 'tout': 'Tout'};

String _usd(Object? n) => Elk.money(n, 'USD');
String _op(Object? code) => _ops[code] ?? '${code ?? '—'}';

/// Début de période (heure locale, minuit) au format ISO UTC, ou null pour « Tout ».
String? sinceOf(String periode, [DateTime? now]) {
  if (periode == 'tout') return null;
  final n = now ?? DateTime.now();
  var d = DateTime(n.year, n.month, n.day);
  if (periode == 'semaine') d = d.subtract(const Duration(days: 6));
  if (periode == 'mois') d = d.subtract(const Duration(days: 29));
  return d.toUtc().toIso8601String();
}

class MomoPage extends StatefulWidget {
  const MomoPage({super.key, required this.data, required this.profile});
  final DataService data;
  final Profile profile;
  @override
  State<MomoPage> createState() => _MomoPageState();
}

class _MomoPageState extends State<MomoPage> {
  bool loading = true;
  String? error;
  List<JsonRow> comptes = [], transactions = [];
  String periode = 'tout';
  Object? compteFiltre; // id momo_comptes, null = tous
  String? typeFiltre;

  DataService get data => widget.data;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    final r = await data.select('momo_comptes', const Query(orderBy: 'id'));
    comptes = r.data ?? [];
    error = r.error;
    await _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final from = sinceOf(periode);
    final r = await data.select(
      'momo_transactions',
      Query(
        embed: const ['momo_comptes(operateur)'],
        eq: {'compte_id': ?compteFiltre, 'type': ?typeFiltre},
        gte: {'cree_le': ?from},
        orderBy: 'cree_le',
        ascending: false,
        limit: 500,
      ),
    );
    if (!mounted) return;
    setState(() {
      transactions = r.data ?? [];
      error ??= r.error;
      loading = false;
    });
  }

  void _filter(VoidCallback change) {
    setState(() {
      change();
      loading = true;
    });
    _loadTransactions();
  }

  Future<void> _newTransaction() async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _TransactionDialog(data: data, profile: widget.profile, comptes: comptes),
    );
    if (res == null || !mounted) return;
    toast(context, '${_types[res.data!['type']] ?? 'Transaction'} enregistré${savedSuffix(res.offline)}');
    _filter(() {});
  }

  Future<void> _releve(JsonRow compte) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _ReleveDialog(data: data, compte: compte),
    );
    if (res == null || !mounted) return;
    toast(context, 'Solde ${_op(compte['operateur'])} mis à jour${savedSuffix(res.offline)}');
    _loadAll();
  }

  Future<void> _setStatut(JsonRow t, String statut) async {
    final res = await data.update('momo_transactions', t['id'] as Object, {'statut': statut});
    if (!mounted) return;
    toast(context, res.ok ? 'Statut mis à jour${savedSuffix(res.offline)}' : 'Erreur : ${res.error}');
    _filter(() {});
  }

  @override
  Widget build(BuildContext context) {
    final total = comptes.fold<num>(0, (s, c) => s + ((c['solde'] as num?) ?? 0));
    num vol = 0, frais = 0;
    var ko = 0;
    for (final t in transactions) {
      if (t['statut'] == 'reussi') {
        vol += (t['montant'] as num?) ?? 0;
        frais += (t['frais'] as num?) ?? 0;
      } else {
        ko++;
      }
    }
    final muted = Theme.of(context).hintColor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Mobile Money',
          subtitle: 'Montants en USD. Les soldes sont des relevés saisis à la main, ils ne sont pas recalculés.',
          actions: [
            FilledButton.icon(
              onPressed: comptes.isEmpty ? null : _newTransaction,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nouvelle transaction'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final c in comptes)
              Kpi(
                _op(c['operateur']),
                _usd(c['solde']),
                footer: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${total == 0 ? 0 : (((c['solde'] as num?) ?? 0) / total * 100).round()} % du float (${_usd(total)})',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                    TextButton(onPressed: () => _releve(c), child: const Text('Relevé')),
                  ],
                ),
              ),
            if (comptes.isEmpty && !loading) Text('Aucun compte opérateur.', style: TextStyle(color: muted)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            Kpi('Transactions', '${transactions.length}'),
            Kpi('Volume réussi', _usd(vol)),
            Kpi('Frais / commissions', _usd(frais)),
            Kpi('Échecs / en attente', '$ko'),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: dropdown<String>('Période', periode, _periodes, (v) => _filter(() => periode = v!)),
            ),
            SizedBox(
              width: 200,
              child: dropdown<Object?>('Opérateur', compteFiltre, {
                null: 'Tous opérateurs',
                for (final c in comptes) c['id']: _op(c['operateur']),
              }, (v) => _filter(() => compteFiltre = v)),
            ),
            SizedBox(
              width: 170,
              child: dropdown<String?>('Type', typeFiltre, {
                null: 'Tous types',
                ..._types,
              }, (v) => _filter(() => typeFiltre = v)),
            ),
            Text(
              '${transactions.length} transaction${transactions.length > 1 ? 's' : ''}',
              style: const TextStyle(color: Elk.accentText, fontWeight: FontWeight.w700),
            ),
            OutlinedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Erreur : $error', style: const TextStyle(color: Elk.crit)),
          ),
        TableCard(
          loading: loading,
          empty: 'Aucune transaction sur cette période.',
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Opérateur')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Client')),
            DataColumn(label: Text('Montant'), numeric: true),
            DataColumn(label: Text('Frais'), numeric: true),
            DataColumn(label: Text('Statut')),
          ],
          rows: [
            for (final t in transactions)
              DataRow(
                cells: [
                  DataCell(Text(_date(t['cree_le']))),
                  DataCell(Text(_op((t['momo_comptes'] as Map?)?['operateur']))),
                  DataCell(Text(_types[t['type']] ?? '${t['type']}')),
                  DataCell(Text('${t['client_tel'] ?? '—'}')),
                  DataCell(Text(_usd(t['montant']))),
                  DataCell(Text(_usd(t['frais']))),
                  DataCell(
                    t['statut'] == 'en_attente'
                        // une transaction en attente peut être confirmée ou marquée en échec
                        ? DropdownButton<String>(
                            value: 'en_attente',
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final e in _statuts.entries)
                                DropdownMenuItem(value: e.key, child: Pill(e.value.$1, e.value.$2)),
                            ],
                            onChanged: (v) => v == null || v == 'en_attente' ? null : _setStatut(t, v),
                          )
                        : Pill(_statuts[t['statut']]?.$1 ?? '${t['statut']}', _statuts[t['statut']]?.$2 ?? muted),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static String _date(Object? t) {
    final d = DateTime.tryParse('$t');
    return d == null ? '—' : DateFormat('d MMM HH:mm', 'fr_FR').format(d.toLocal());
  }
}

// ------------------------------------------------------------------ dialogues
class _TransactionDialog extends StatefulWidget {
  const _TransactionDialog({required this.data, required this.profile, required this.comptes});
  final DataService data;
  final Profile profile;
  final List<JsonRow> comptes;
  @override
  State<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> {
  final _form = GlobalKey<FormState>();
  final _montant = TextEditingController();
  final _frais = TextEditingController();
  final _tel = TextEditingController();
  late Object? compte = widget.comptes.first['id'];
  String type = 'depot', statut = 'reussi';
  bool busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final res = await widget.data.insert('momo_transactions', {
      'compte_id': compte,
      'type': type,
      'montant': parseAmount(_montant.text),
      'frais': parseAmount(_frais.text) ?? 0,
      'client_tel': _tel.text.trim().isEmpty ? null : _tel.text.trim(),
      'statut': statut,
      'agent_id': widget.profile.userId,
    });
    if (!mounted) return;
    if (!res.ok) {
      setState(() => busy = false);
      return toast(context, 'Erreur : ${res.error}');
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouvelle transaction'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: formGrid([
          dropdown<Object?>('Opérateur', compte, {
            for (final c in widget.comptes) c['id']: _op(c['operateur']),
          }, (v) => compte = v),
          dropdown<String>('Type', type, _types, (v) => type = v ?? type),
          AmountField(controller: _montant, label: 'Montant (USD)'),
          AmountField(controller: _frais, label: 'Frais / commission (USD)', allowZero: true, required: false),
          TextFormField(
            controller: _tel,
            decoration: const InputDecoration(labelText: 'Téléphone client', hintText: '+243…'),
            keyboardType: TextInputType.phone,
          ),
          dropdown<String>('Statut', statut, {
            for (final e in _statuts.entries) e.key: e.value.$1,
          }, (v) => statut = v ?? statut),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer')),
    ],
  );
}

class _ReleveDialog extends StatefulWidget {
  const _ReleveDialog({required this.data, required this.compte});
  final DataService data;
  final JsonRow compte;
  @override
  State<_ReleveDialog> createState() => _ReleveDialogState();
}

class _ReleveDialogState extends State<_ReleveDialog> {
  final _form = GlobalKey<FormState>();
  late final _solde = TextEditingController(text: '${widget.compte['solde'] ?? 0}');
  bool busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final res = await widget.data.update('momo_comptes', widget.compte['id'] as Object, {
      'solde': parseAmount(_solde.text),
    });
    if (!mounted) return;
    if (!res.ok) {
      setState(() => busy = false);
      return toast(context, 'Erreur : ${res.error}');
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Relevé de solde · ${_op(widget.compte['operateur'])}'),
    content: SizedBox(
      width: 360,
      child: Form(
        key: _form,
        child: AmountField(controller: _solde, label: 'Nouveau solde relevé (USD)', allowZero: true),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Mise à jour…' : 'Mettre à jour')),
    ],
  );
}
