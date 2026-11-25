// Module Clients : fiches (particuliers / entreprises) + chiffre d'affaires cumulé.
// CA cumulé = dossiers voyage + commandes fourniture, hors annulés, converti en USD.
// Chaque agent ne voit que ce que son rôle autorise (RLS) : un rôle sans « fourniture »
// verra un CA sans les commandes — l'écran l'indique.
import 'package:flutter/material.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/remote.dart';
import '../../profile.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets.dart';

const typesClient = {'particulier': 'Particulier', 'entreprise': 'Entreprise'};
const segments = ['', 'VIP', 'Grand compte', 'Régulier', 'Prospect'];

String _usd(num n) => Elk.money((n * 100).round() / 100, 'USD');
num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

class ClientStats {
  int dossiers = 0, commandes = 0;
  num ca = 0;
}

/// CA cumulé par client (USD), d'après les dossiers et commandes non annulés.
Map<String, ClientStats> statsClients(List<JsonRow> dossiers, List<JsonRow> commandes, List<JsonRow> devises) {
  final taux = {for (final d in devises) '${d['id']}': _num(d['taux']) == 0 ? 1 : _num(d['taux'])};
  final out = <String, ClientStats>{};
  for (final d in dossiers) {
    if (d['statut'] == 'annule') continue;
    final s = out.putIfAbsent('${d['client_id']}', ClientStats.new);
    s.dossiers++;
    s.ca += _num(d['montant']) / (taux['${d['devise_id']}'] ?? 1);
  }
  for (final c in commandes) {
    if (c['statut'] == 'annulee') continue;
    final s = out.putIfAbsent('${c['client_id']}', ClientStats.new);
    s.commandes++;
    s.ca += _num(c['total']);
  }
  return out;
}

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key, required this.data, required this.profile});
  final DataService data;
  final Profile profile;
  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  bool loading = true;
  String? error;
  List<JsonRow> clients = [], dossiers = [], commandes = [], devises = [];
  String recherche = '', type = '', tri = 'nom';

  DataService get data => widget.data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final p = widget.profile;
    final r = await Future.wait([
      data.select('clients', const Query(orderBy: 'nom')),
      data.select('devises', const Query(orderBy: 'id')),
      // on ne lit que ce que le rôle autorise (sinon la base renverrait de toute façon une liste vide)
      if (p.can('voyage')) data.select('dossiers', const Query(limit: 5000)),
      if (p.can('fourniture')) data.select('commandes', const Query(limit: 5000)),
    ]);
    if (!mounted) return;
    var i = 2;
    setState(() {
      clients = r[0].data ?? [];
      devises = r[1].data ?? [];
      dossiers = p.can('voyage') ? (r[i++].data ?? []) : [];
      commandes = p.can('fourniture') ? (r[i++].data ?? []) : [];
      error = r.map((x) => x.error).whereType<String>().firstOrNull;
      loading = false;
    });
    if (Navigation.prendreAction('clients') == 'nouveau') _edit(); // bouton de l'accueil
  }

  Future<void> _edit([JsonRow? c]) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _ClientDialog(data: data, profile: widget.profile, client: c),
    );
    if (res == null || !mounted) return;
    toast(context, 'Client ${res.data?['nom'] ?? ''} enregistré${savedSuffix(res.offline)}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final stats = statsClients(dossiers, commandes, devises);
    ClientStats st(JsonRow c) => stats['${c['id']}'] ?? ClientStats();
    final q = recherche.trim().toLowerCase();
    final visibles = clients.where((c) {
      if (type.isNotEmpty && c['type'] != type) return false;
      if (q.isEmpty) return true;
      return ['nom', 'telephone', 'ville', 'email', 'segment'].any((k) => '${c[k] ?? ''}'.toLowerCase().contains(q));
    }).toList();
    if (tri == 'ca') visibles.sort((a, b) => st(b).ca.compareTo(st(a).ca));

    final caTotal = stats.values.fold<num>(0, (s, x) => s + x.ca);
    final top = clients.isEmpty ? null : (List.of(clients)..sort((a, b) => st(b).ca.compareTo(st(a).ca))).first;
    final partiel = !widget.profile.can('voyage') || !widget.profile.can('fourniture');
    final muted = Theme.of(context).hintColor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Clients',
          subtitle: 'Fiches clients et chiffre d’affaires cumulé (voyage + fourniture, hors annulés, en USD).',
          actions: [
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
            FilledButton.icon(
              onPressed: loading ? null : () => _edit(),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Nouveau client'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            Kpi('Clients', '${clients.length}'),
            Kpi('Entreprises', '${clients.where((c) => c['type'] == 'entreprise').length}'),
            Kpi('CA cumulé', _usd(caTotal)),
            Kpi(
              'Meilleur client',
              top == null || st(top).ca == 0 ? '—' : '${top['nom']}',
              footer: top == null || st(top).ca == 0 ? null : Text(_usd(st(top).ca), style: TextStyle(color: muted)),
            ),
          ],
        ),
        if (partiel)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'CA partiel : ton rôle ne donne pas accès à '
              '${!widget.profile.can('voyage') ? 'Voyage' : ''}'
              '${!widget.profile.can('voyage') && !widget.profile.can('fourniture') ? ' ni ' : ''}'
              '${!widget.profile.can('fourniture') ? 'Fourniture' : ''}.',
              style: TextStyle(color: muted, fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                decoration: const InputDecoration(labelText: 'Rechercher', prefixIcon: Icon(Icons.search, size: 18)),
                onChanged: (v) => setState(() => recherche = v),
              ),
            ),
            SizedBox(
              width: 170,
              child: dropdown<String>('Type', type, {
                '': 'Tous',
                ...typesClient,
              }, (v) => setState(() => type = v ?? '')),
            ),
            SizedBox(
              width: 170,
              child: dropdown<String>('Tri', tri, const {
                'nom': 'Par nom',
                'ca': 'Par CA',
              }, (v) => setState(() => tri = v ?? 'nom')),
            ),
            Text(
              '${visibles.length} client${visibles.length > 1 ? 's' : ''}',
              style: const TextStyle(color: Elk.accentText, fontWeight: FontWeight.w700),
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
          empty: clients.isEmpty ? 'Aucun client. Clique « Nouveau client ».' : 'Aucun client ne correspond.',
          columns: const [
            DataColumn(label: Text('Nom')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Téléphone')),
            DataColumn(label: Text('Ville')),
            DataColumn(label: Text('Segment')),
            DataColumn(label: Text('Dossiers'), numeric: true),
            DataColumn(label: Text('Commandes'), numeric: true),
            DataColumn(label: Text('CA cumulé'), numeric: true),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final c in visibles)
              DataRow(
                cells: [
                  DataCell(Text('${c['nom']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(c['type'] == 'entreprise' ? const Pill('Entreprise', Elk.info) : Pill('Particulier', muted)),
                  DataCell(Text('${c['telephone'] ?? '—'}')),
                  DataCell(Text('${c['ville'] ?? '—'}')),
                  DataCell((c['segment'] ?? '') == '' ? const Text('—') : Pill('${c['segment']}', Elk.accentText)),
                  DataCell(Text('${st(c).dossiers}')),
                  DataCell(Text('${st(c).commandes}')),
                  DataCell(Text(_usd(st(c).ca), style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(
                    IconButton(
                      tooltip: 'Modifier la fiche',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _edit(c),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _ClientDialog extends StatefulWidget {
  const _ClientDialog({required this.data, required this.profile, this.client});
  final DataService data;
  final Profile profile;
  final JsonRow? client; // null = création
  @override
  State<_ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<_ClientDialog> {
  final _form = GlobalKey<FormState>();
  late final c = widget.client;
  late final _nom = TextEditingController(text: '${c?['nom'] ?? ''}');
  late final _tel = TextEditingController(text: '${c?['telephone'] ?? ''}');
  late final _ville = TextEditingController(text: '${c?['ville'] ?? 'Lubumbashi'}');
  late final _email = TextEditingController(text: '${c?['email'] ?? ''}');
  late String type = typesClient.containsKey(c?['type']) ? c!['type'] as String : 'particulier';
  late String segment = segments.contains(c?['segment'] ?? '') ? '${c?['segment'] ?? ''}' : '';
  bool busy = false;

  String? _opt(TextEditingController t) => t.text.trim().isEmpty ? null : t.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final row = {
      'nom': _nom.text.trim(),
      'type': type,
      'telephone': _opt(_tel),
      'ville': _opt(_ville),
      'email': _opt(_email),
      'segment': segment.isEmpty ? null : segment,
    };
    final res = c == null
        ? await widget.data.insert('clients', {...row, 'cree_par': widget.profile.userId})
        : await widget.data.update('clients', c!['id'] as Object, row);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => busy = false);
      return toast(context, 'Erreur : ${res.error}');
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(c == null ? 'Nouveau client' : 'Modifier ${c!['nom']}'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: formGrid([
          TextFormField(
            controller: _nom,
            decoration: const InputDecoration(labelText: 'Nom'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Nom requis' : null,
          ),
          dropdown<String>('Type', type, typesClient, (v) => type = v ?? type),
          TextFormField(
            controller: _tel,
            decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+243…'),
            keyboardType: TextInputType.phone,
          ),
          TextFormField(
            controller: _ville,
            decoration: const InputDecoration(labelText: 'Ville'),
          ),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'E-mail'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) =>
                (v ?? '').trim().isEmpty || (v!.contains('@') && v.contains('.')) ? null : 'E-mail invalide',
          ),
          dropdown<String>('Segment', segment, {
            for (final s in segments) s: s.isEmpty ? '—' : s,
          }, (v) => segment = v ?? ''),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer')),
    ],
  );
}
