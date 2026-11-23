// Module Voyage (référence pour porter les autres modules) : KPIs, liste, création.
// Équivalent de web/js/modules/voyage.js — toutes les données passent par DataService.
import 'package:flutter/material.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/remote.dart';
import '../../profile.dart';
import '../theme.dart';
import '../widgets.dart';

const _types = {'billet': 'Billet', 'visa': 'Visa', 'hotel': 'Hôtel', 'assurance': 'Assurance', 'package': 'Package'};
const _statuts = {
  'devis': ('Devis', Elk.info),
  'confirme': ('Confirmé', Elk.ok),
  'paye': ('Payé', Elk.ok),
  'en_cours': ('En cours', Elk.warn),
  'annule': ('Annulé', Elk.crit),
};

class VoyagePage extends StatefulWidget {
  const VoyagePage({super.key, required this.data, required this.profile});
  final DataService data;
  final Profile profile;
  @override
  State<VoyagePage> createState() => _VoyagePageState();
}

class _VoyagePageState extends State<VoyagePage> {
  bool loading = true;
  String? error;
  List<JsonRow> dossiers = [], clients = [], devises = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final d = widget.data;
    final res = await Future.wait([
      d.select('dossiers', const Query(embed: ['clients(nom)', 'devises(code)'], orderBy: 'cree_le', ascending: false)),
      d.select('clients', const Query(orderBy: 'nom')),
      d.select('devises', const Query(orderBy: 'id')),
    ]);
    if (!mounted) return;
    setState(() {
      loading = false;
      error = res.firstWhere((r) => !r.ok, orElse: () => res.first).error;
      dossiers = res[0].data ?? [];
      clients = res[1].data ?? [];
      devises = res[2].data ?? [];
    });
  }

  Future<void> _create() async {
    final saved = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _DossierDialog(data: widget.data, profile: widget.profile, clients: clients, devises: devises),
    );
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Dossier ${saved.data!['ref']} enregistré${savedSuffix(saved.offline)}')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    var ok = 0, pend = 0;
    num sum = 0;
    for (final d in dossiers) {
      if (d['statut'] == 'confirme' || d['statut'] == 'paye') {
        ok++;
      } else if (d['statut'] != 'annule') {
        pend++;
      }
      sum += (d['montant'] as num?) ?? 0;
    }
    final muted = Theme.of(context).hintColor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Voyage',
          subtitle: 'Dossiers clients (billets, visa, hôtel, assurance, package).',
          actions: [
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
            FilledButton.icon(
              onPressed: clients.isEmpty || devises.isEmpty ? null : _create,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nouveau dossier'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            Kpi('Dossiers', '${dossiers.length}'),
            Kpi('Confirmés / payés', '$ok'),
            Kpi('En cours / devis', '$pend'),
            Kpi('Montant total', '${Elk.fmt(sum)} \$'),
          ],
        ),
        const SizedBox(height: 16),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Erreur : $error', style: const TextStyle(color: Elk.crit)),
          ),
        TableCard(
          loading: loading,
          empty: 'Aucun dossier. Clique « Nouveau dossier ».',
          columns: const [
            DataColumn(label: Text('Réf.')),
            DataColumn(label: Text('Client')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Destination')),
            DataColumn(label: Text('Montant'), numeric: true),
            DataColumn(label: Text('Statut')),
          ],
          rows: [
            for (final d in dossiers)
              DataRow(
                cells: [
                  DataCell(Text('${d['ref'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text('${(d['clients'] as Map?)?['nom'] ?? '—'}')),
                  DataCell(Text(_types[d['type']] ?? '${d['type']}')),
                  DataCell(Text('${d['destination'] ?? '—'}')),
                  DataCell(Text(Elk.money(d['montant'], (d['devises'] as Map?)?['code'] as String?))),
                  DataCell(Pill(_statuts[d['statut']]?.$1 ?? '${d['statut']}', _statuts[d['statut']]?.$2 ?? muted)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _DossierDialog extends StatefulWidget {
  const _DossierDialog({required this.data, required this.profile, required this.clients, required this.devises});
  final DataService data;
  final Profile profile;
  final List<JsonRow> clients, devises;
  @override
  State<_DossierDialog> createState() => _DossierDialogState();
}

class _DossierDialogState extends State<_DossierDialog> {
  final _form = GlobalKey<FormState>();
  final _dest = TextEditingController();
  final _montant = TextEditingController();
  late Object? client = widget.clients.first['id'];
  late Object? devise = widget.devises.first['id'];
  String type = 'billet', statut = 'devis';
  bool busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final res = await widget.data.insert('dossiers', {
      'ref': 'ELK-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
      'client_id': client,
      'type': type,
      'destination': _dest.text.trim().isEmpty ? null : _dest.text.trim(),
      'montant': double.parse(_montant.text.replaceAll(' ', '').replaceAll(',', '.')),
      'devise_id': devise,
      'statut': statut,
      'agent_id': widget.profile.userId,
    });
    if (!mounted) return;
    setState(() => busy = false);
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : ${res.error}')));
      return;
    }
    Navigator.pop(context, res);
  }

  DropdownButtonFormField<T> _dd<T>(String label, T value, Map<T, String> items, ValueChanged<T?> onChanged) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouveau dossier'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final w in <Widget>[
              _dd<Object?>('Client', client, {
                for (final c in widget.clients) c['id']: '${c['nom']}',
              }, (v) => client = v),
              _dd<String>('Type', type, _types, (v) => type = v ?? type),
              TextFormField(
                controller: _dest,
                decoration: const InputDecoration(labelText: 'Destination'),
              ),
              TextFormField(
                controller: _montant,
                decoration: const InputDecoration(labelText: 'Montant'),
                validator: (v) {
                  final n = double.tryParse((v ?? '').replaceAll(' ', '').replaceAll(',', '.'));
                  return n == null || n < 0 ? 'Montant invalide' : null;
                },
              ),
              _dd<Object?>('Devise', devise, {
                for (final d in widget.devises) d['id']: '${d['code']}',
              }, (v) => devise = v),
              _dd<String>('Statut', statut, {
                for (final e in _statuts.entries) e.key: e.value.$1,
              }, (v) => statut = v ?? statut),
            ])
              SizedBox(width: 253, child: w),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer')),
    ],
  );
}
