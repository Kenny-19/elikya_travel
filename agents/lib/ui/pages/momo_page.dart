// Module Mobile Money — pensé pour être TRÈS simple :
// - trois gros boutons : Dépôt · Retrait · Transfert (une ligne d'explication sous chacun) ;
// - formulaire court : opérateur en grandes pastilles, montant, téléphone, « l'opération a réussi » ;
// - opérations en attente : deux boutons clairs « C'est passé » / « Ça n'a pas marché ».
// Le solde de chaque opérateur bouge tout seul à chaque opération réussie (déclencheur db/momo_soldes.sql) ;
// « Mettre à jour le solde » le corrige d'après le téléphone de l'opérateur. Montants en USD.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/remote.dart';
import '../../profile.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets.dart';

const _ops = {'airtel': 'Airtel Money', 'orange': 'Orange Money', 'mpesa': 'M-Pesa'};
const _couleursOps = {'airtel': Color(0xFFE40000), 'orange': Color(0xFFFF6A00), 'mpesa': Color(0xFF0B8F3C)};
const _types = {'depot': 'Dépôt', 'retrait': 'Retrait', 'transfert': 'Transfert'};
const _explications = {
  'depot': 'Le client donne de l’argent et le reçoit sur son téléphone.',
  'retrait': 'Le client retire de l’argent de son téléphone et repart avec des billets.',
  'transfert': 'Le client envoie de l’argent vers un autre numéro.',
};
const _iconesTypes = {'depot': Icons.south_west, 'retrait': Icons.north_east, 'transfert': Icons.swap_horiz};
const _statuts = {'reussi': ('Réussi', Elk.ok), 'en_attente': ('En attente', Elk.warn), 'echec': ('Échec', Elk.crit)};

String _usd(Object? n) => Elk.money(n, 'USD');
String _op(Object? code) => _ops[code] ?? '${code ?? '—'}';
num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

/// Effet d'une opération RÉUSSIE sur le solde de l'opérateur (argent électronique) :
/// dépôt et transfert le font baisser, retrait le fait monter. Même règle que db/momo_soldes.sql (déclencheur).
num effetMomo(Object? type, num montant) => type == 'retrait' ? montant : -montant;

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
  bool loading = true, avant = false;
  String? error;
  List<JsonRow> comptes = [], transactions = [];

  DataService get data => widget.data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final r = await Future.wait([
      data.select('momo_comptes', const Query(orderBy: 'id')),
      data.select(
        'momo_transactions',
        Query(
          embed: const ['momo_comptes(operateur)'],
          gte: {'cree_le': sinceOf('mois')!},
          orderBy: 'cree_le',
          ascending: false,
          limit: 800,
        ),
      ),
      // les opérations en attente, même anciennes
      data.select('momo_transactions', const Query(embed: ['momo_comptes(operateur)'], eq: {'statut': 'en_attente'})),
    ]);
    if (!mounted) return;
    final vus = <Object?>{};
    setState(() {
      comptes = r[0].data ?? [];
      transactions = [...?r[1].data, ...?r[2].data].where((t) => vus.add(t['id'])).toList()
        ..sort((a, b) => '${b['cree_le']}'.compareTo('${a['cree_le']}'));
      error = r.map((x) => x.error).whereType<String>().firstOrNull;
      loading = false;
    });
    // boutons de l'accueil « Dépôt / Retrait mobile money »
    final action = Navigation.prendreAction('momo');
    if (action != null && _types.containsKey(action) && comptes.isNotEmpty) _operation(action);
  }

  Future<void> _operation(String type) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _OperationDialog(data: data, profile: widget.profile, comptes: comptes, type: type),
    );
    if (res == null || !mounted) return;
    toast(context, '${_types[type]} noté${savedSuffix(res.offline)}');
    _load();
  }

  Future<void> _statut(JsonRow t, String statut) async {
    final res = await data.update('momo_transactions', t['id'] as Object, {'statut': statut});
    if (!mounted) return;
    toast(
      context,
      res.ok
          ? (statut == 'reussi' ? 'Opération confirmée ✓' : 'Opération marquée en échec') + savedSuffix(res.offline)
          : 'Erreur : ${res.error}',
    );
    _load();
  }

  Future<void> _releve(JsonRow compte) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _ReleveDialog(data: data, compte: compte),
    );
    if (res == null || !mounted) return;
    toast(context, 'Solde ${_op(compte['operateur'])} mis à jour${savedSuffix(res.offline)}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    final debutJour = sinceOf('jour')!;
    final duJour = transactions.where((t) => '${t['cree_le']}'.compareTo(debutJour) >= 0).toList();
    final attente = transactions.where((t) => t['statut'] == 'en_attente').toList();
    final reussies = duJour.where((t) => t['statut'] == 'reussi');
    final volume = reussies.fold<num>(0, (s, t) => s + _num(t['montant']));
    final frais = reussies.fold<num>(0, (s, t) => s + _num(t['frais']));
    final avantJour = transactions
        .where((t) => '${t['cree_le']}'.compareTo(debutJour) < 0 && t['statut'] != 'en_attente')
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Mobile money',
          subtitle: 'Choisissez l’opération demandée par le client.',
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
          runSpacing: 14,
          children: [
            for (final t in _types.keys)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 300,
                  maxWidth: 300,
                  minHeight: 124,
                ), // même taille, peut grandir
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: comptes.isEmpty ? null : () => _operation(t),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: Elk.accent,
                            child: Icon(_iconesTypes[t], color: Elk.navy, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_types[t]!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                                Text(_explications[t]!, style: TextStyle(color: muted, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Erreur : $error', style: const TextStyle(color: Elk.crit)),
          ),
        if (attente.isNotEmpty) ...[
          const SizedBox(height: 24),
          const TitreSection('À confirmer'),
          const SizedBox(height: 8),
          for (final t in attente)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: Elk.warn.withValues(alpha: .06),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(Icons.hourglass_top, color: Elk.warn),
                    Text(
                      '${_types[t['type']] ?? t['type']} ${_usd(t['montant'])} · ${_op((t['momo_comptes'] as Map?)?['operateur'])}'
                      '${t['client_tel'] != null ? ' · ${t['client_tel']}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Elk.ok, foregroundColor: Colors.white),
                      onPressed: () => _statut(t, 'reussi'),
                      icon: const Icon(Icons.check),
                      label: const Text('C’est passé'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _statut(t, 'echec'),
                      icon: const Icon(Icons.close),
                      label: const Text('Ça n’a pas marché'),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
        const TitreSection('Soldes des opérateurs'),
        Text(
          'Ils bougent tout seuls à chaque opération réussie : un dépôt ou un transfert les fait baisser, un retrait les fait monter. '
          'Si le téléphone de l’opérateur affiche autre chose, corrigez avec « Mettre à jour le solde ».',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in comptes)
              SizedBox(
                width: 250,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(radius: 6, backgroundColor: _couleursOps[c['operateur']] ?? Elk.slate),
                            const SizedBox(width: 8),
                            Text(_op(c['operateur']), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(_usd(c['solde']), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        TextButton(onPressed: () => _releve(c), child: const Text('Mettre à jour le solde')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const TitreSection('Aujourd’hui'),
            const SizedBox(width: 14),
            if (duJour.isNotEmpty)
              Text(
                '${duJour.length} opération${duJour.length > 1 ? 's' : ''} · ${_usd(volume)} · commissions ${_usd(frais)}',
                style: TextStyle(color: muted),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (duJour.isEmpty)
          const EtatVide(icone: Icons.phone_android, texte: 'Aucune opération aujourd’hui.')
        else
          for (final t in duJour) _ligne(t),
        const SizedBox(height: 14),
        if (avantJour.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() => avant = !avant),
            icon: Icon(avant ? Icons.expand_less : Icons.expand_more),
            label: Text(avant ? 'Masquer les jours précédents' : 'Voir les jours précédents (${avantJour.length})'),
          ),
        if (avant)
          for (final t in avantJour) _ligne(t, avecDate: true),
      ],
    );
  }

  Widget _ligne(JsonRow t, {bool avecDate = false}) {
    final st = _statuts[t['statut']] ?? ('${t['statut']}', Elk.slate);
    final quand = t['cree_le'] == null
        ? ''
        : DateFormat(avecDate ? 'd MMM · HH:mm' : 'HH:mm', 'fr_FR').format(DateTime.parse('${t['cree_le']}').toLocal());
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_iconesTypes[t['type']] ?? Icons.phone_android, color: Elk.navy2),
        title: Text(
          '${_types[t['type']] ?? t['type']} · ${_op((t['momo_comptes'] as Map?)?['operateur'])}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('$quand${t['client_tel'] != null ? ' · ${t['client_tel']}' : ''}'),
        trailing: Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_usd(t['montant']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Pill(st.$1, st.$2),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ nouvelle opération
class _OperationDialog extends StatefulWidget {
  const _OperationDialog({required this.data, required this.profile, required this.comptes, required this.type});
  final DataService data;
  final Profile profile;
  final List<JsonRow> comptes;
  final String type;
  @override
  State<_OperationDialog> createState() => _OperationDialogState();
}

class _OperationDialogState extends State<_OperationDialog> {
  final _form = GlobalKey<FormState>();
  final _montant = TextEditingController();
  final _frais = TextEditingController();
  final _tel = TextEditingController();
  Object? compte;
  bool reussi = true, busy = false;

  /// « Solde Airtel : 2 310 $ → après : 2 190 $ », en rouge s'il n'y a pas assez d'argent électronique.
  Widget _apres() {
    final c = widget.comptes.where((x) => x['id'] == compte).firstOrNull;
    final m = parseAmount(_montant.text) ?? 0;
    if (c == null || m <= 0) return const SizedBox.shrink();
    final avant = _num(c['solde']), apres = avant + effetMomo(widget.type, m);
    final manque = apres < 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (manque ? Elk.crit : Elk.info).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solde ${_op(c['operateur'])} : ${_usd(avant)} → après l’opération : ${_usd(apres)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: manque ? Elk.crit : null),
          ),
          if (manque)
            const Text(
              'Attention : il n’y a pas assez d’argent électronique chez cet opérateur pour cette opération.',
              style: TextStyle(color: Elk.crit),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (compte == null) return toast(context, 'Choisissez l’opérateur.');
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final res = await widget.data.insert('momo_transactions', {
      'compte_id': compte,
      'type': widget.type,
      'montant': parseAmount(_montant.text),
      'frais': parseAmount(_frais.text) ?? 0,
      'client_tel': _tel.text.trim().isEmpty ? null : _tel.text.trim(),
      'statut': reussi ? 'reussi' : 'en_attente',
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
    title: Row(
      children: [
        Icon(_iconesTypes[widget.type], color: Elk.accentText, size: 28),
        const SizedBox(width: 10),
        Text('${_types[widget.type]} mobile money'),
      ],
    ),
    content: SizedBox(
      width: 540,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Etape('1', 'Quel opérateur ?'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in widget.comptes)
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: CircleAvatar(radius: 7, backgroundColor: _couleursOps[c['operateur']] ?? Elk.slate),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Text(
                        _op(c['operateur']),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    selected: compte == c['id'],
                    onSelected: (_) => setState(() => compte = c['id']),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Etape('2', 'Combien ?'),
            formGrid([
              TextFormField(
                controller: _montant,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(labelText: 'Montant (USD)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (parseAmount(v) ?? 0) > 0 ? null : 'Indiquez le montant',
                onChanged: (_) => setState(() {}), // solde après l'opération recalculé
              ),
              AmountField(controller: _frais, label: 'Commission (facultatif)', allowZero: true, required: false),
            ]),
            _apres(),
            const SizedBox(height: 16),
            const Etape('3', 'Téléphone du client'),
            TextField(
              controller: _tel,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Numéro', hintText: '+243…'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: reussi,
              onChanged: (v) => setState(() => reussi = v),
              title: Text(
                reussi ? 'L’opération a réussi' : 'Pas encore confirmée (en attente)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Si le réseau n’a pas encore confirmé, désactivez : vous confirmerez plus tard.'),
            ),
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

// ------------------------------------------------------------------ relevé de solde
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
    title: Text('Solde ${_op(widget.compte['operateur'])}'),
    content: SizedBox(
      width: 380,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Regardez le solde affiché sur le téléphone de l’opérateur et recopiez-le.',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 12),
            AmountField(controller: _solde, label: 'Solde actuel (USD)', allowZero: true),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Mise à jour…' : 'Mettre à jour')),
    ],
  );
}
