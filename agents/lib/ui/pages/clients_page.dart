// Module Clients — pensé pour être TRÈS simple :
// une grande barre de recherche, puis une carte par client (nom, téléphone, ce qu'il a acheté),
// et une fiche courte : « Particulier ou entreprise ? », nom, téléphone ; le reste est facultatif.
// « A acheté pour » = dossiers voyage + commandes fourniture, hors annulés, converti en USD.
// Chaque agent ne voit que ce que son rôle autorise (RLS) : un rôle sans « fourniture »
// verra un total sans les commandes — l'écran le dit en clair.
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
String _pluriel(int n, String mot) => '$n $mot${n > 1 ? 's' : ''}';

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

class _ClientsPageState extends State<ClientsPage> with AutoRafraichi {
  @override
  void rafraichir() => _load(silencieux: true); // mise à jour automatique (navigation.dart)

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

  Future<void> _load({bool silencieux = false}) async {
    if (!silencieux) setState(() => loading = true);
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

    final p = widget.profile;
    final muted = Theme.of(context).hintColor;
    final manque = [if (!p.can('voyage')) 'les voyages', if (!p.can('fourniture')) 'les commandes de fourniture'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Clients',
          subtitle: 'Retrouvez un client, ou ajoutez-en un nouveau.',
          actions: [
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 460,
              child: TextField(
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(
                  labelText: 'Chercher un client',
                  hintText: 'Nom, téléphone ou ville',
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                ),
                onChanged: (v) => setState(() => recherche = v),
              ),
            ),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  textStyle: const TextStyle(fontFamily: Elk.font, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                onPressed: loading ? null : () => _edit(),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Nouveau client'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in const [('', 'Tous'), ('particulier', 'Particuliers'), ('entreprise', 'Entreprises')])
              ChoiceChip(
                showCheckmark: false,
                label: Text(f.$2),
                selected: type == f.$1,
                onSelected: (_) => setState(() => type = f.$1),
              ),
            const SizedBox(width: 12),
            ChoiceChip(
              showCheckmark: false,
              avatar: const Icon(Icons.sort_by_alpha, size: 18),
              label: const Text('De A à Z'),
              selected: tri == 'nom',
              onSelected: (_) => setState(() => tri = 'nom'),
            ),
            ChoiceChip(
              showCheckmark: false,
              avatar: const Icon(Icons.star_outline, size: 18),
              label: const Text('Meilleurs clients'),
              selected: tri == 'ca',
              onSelected: (_) => setState(() => tri = 'ca'),
            ),
            const SizedBox(width: 12),
            Text(
              _pluriel(visibles.length, 'client'),
              style: const TextStyle(color: Elk.accentText, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (manque.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Les montants « a acheté pour » ne comptent pas ${manque.join(' ni ')} (votre rôle n’y a pas accès).',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ),
        const SizedBox(height: 14),
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
        else if (visibles.isEmpty)
          EtatVide(
            icone: Icons.person_search_outlined,
            texte: clients.isEmpty
                ? 'Aucun client pour l’instant. Ajoutez-en un avec « Nouveau client ».'
                : 'Aucun client ne correspond à « $recherche ».',
          )
        else
          for (final c in visibles) _carte(c, st(c), muted),
      ],
    );
  }

  Widget _carte(JsonRow c, ClientStats s, Color muted) {
    final nom = '${c['nom'] ?? ''}'.trim();
    final initiales = nom
        .split(RegExp(r'\s+'))
        .where((x) => x.isNotEmpty)
        .take(2)
        .map((x) => x[0].toUpperCase())
        .join();
    final entreprise = c['type'] == 'entreprise';
    final activite = [
      if (s.dossiers > 0) _pluriel(s.dossiers, 'voyage'),
      if (s.commandes > 0) _pluriel(s.commandes, 'commande'),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: entreprise ? Elk.navy2 : Elk.accent.withValues(alpha: .22),
                child: entreprise
                    ? const Icon(Icons.business, color: Colors.white)
                    : Text(
                        initiales,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Elk.navy),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(nom, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        if (entreprise) const Pill('Entreprise', Elk.info),
                        if ((c['segment'] ?? '') != '') Pill('${c['segment']}', Elk.accentText),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (c['telephone'] != null) ...[
                          Icon(Icons.phone_outlined, size: 16, color: muted),
                          Text('${c['telephone']}', style: TextStyle(color: muted, fontSize: 15)),
                        ],
                        if (c['telephone'] != null && c['ville'] != null)
                          Text('  ·  ', style: TextStyle(color: muted, fontSize: 15)),
                        if (c['ville'] != null) Text('${c['ville']}', style: TextStyle(color: muted, fontSize: 15)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (s.ca > 0) ...[
                    Text('A acheté pour', style: TextStyle(color: muted, fontSize: 12.5)),
                    Text(_usd(s.ca), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(activite.join(' · '), style: TextStyle(color: muted, fontSize: 12.5)),
                  ] else
                    Text('Pas encore d’achat', style: TextStyle(color: muted)),
                ],
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: muted),
            ],
          ),
        ),
      ),
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
    title: Text(c == null ? 'Nouveau client' : 'Fiche de ${c!['nom']}'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Etape('1', 'Particulier ou entreprise ?'),
              Wrap(
                spacing: 10,
                children: [
                  for (final t in const [
                    ('particulier', 'Une personne', Icons.person_outline),
                    ('entreprise', 'Une entreprise', Icons.business),
                  ])
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: Icon(t.$3),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: Text(t.$2, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      selected: type == t.$1,
                      onSelected: (_) => setState(() => type = t.$1),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Etape('2', 'Nom et téléphone'),
              TextFormField(
                controller: _nom,
                style: const TextStyle(fontSize: 17),
                decoration: InputDecoration(labelText: type == 'entreprise' ? 'Nom de l’entreprise' : 'Nom complet'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Indiquez le nom' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tel,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+243…'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: c != null,
                  title: const Text('Plus d’informations (facultatif)', style: TextStyle(fontWeight: FontWeight.w700)),
                  childrenPadding: const EdgeInsets.only(bottom: 6),
                  children: [
                    formGrid([
                      TextFormField(
                        controller: _ville,
                        decoration: const InputDecoration(labelText: 'Ville'),
                      ),
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v ?? '').trim().isEmpty || (v!.contains('@') && v.contains('.'))
                            ? null
                            : 'E-mail invalide',
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Type de client :', style: TextStyle(color: Theme.of(context).hintColor)),
                          for (final s in segments)
                            ChoiceChip(
                              showCheckmark: false,
                              label: Text(s.isEmpty ? 'Aucun' : s),
                              selected: segment == s,
                              onSelected: (_) => setState(() => segment = s),
                            ),
                        ],
                      ),
                    ),
                  ],
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
