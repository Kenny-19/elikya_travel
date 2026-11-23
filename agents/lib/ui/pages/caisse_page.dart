// Module Caisse — équivalent de web/js/modules/caisse.js.
// Sessions journalières (une par jour et par agent), mouvements entrées/sorties, solde théorique,
// clôture avec écart. Suivi uniquement : on JOURNALISE, aucun traitement d'argent.
// Totaux en USD : les montants CDF sont convertis au taux de la table devises.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/remote.dart';
import '../../profile.dart';
import '../theme.dart';
import '../widgets.dart';

const _modules = ['Voyage', 'Fourniture', 'Mobile money', 'Logistique', 'Admin', 'Autre'];
const _sources = {'paiement': 'Paiement', 'depense': 'Dépense', 'momo': 'Mobile money', 'autre': 'Autre'};

String _usd(num n) => Elk.money((n * 100).round() / 100, 'USD');
String _jour(Object? j) {
  final d = DateTime.tryParse('$j');
  return d == null ? '$j' : DateFormat('EEE d MMM y', 'fr_FR').format(d);
}

class CaissePage extends StatefulWidget {
  const CaissePage({super.key, required this.data, required this.profile});
  final DataService data;
  final Profile profile;
  @override
  State<CaissePage> createState() => _CaissePageState();
}

class _CaissePageState extends State<CaissePage> {
  bool loading = true;
  String? error;
  List<JsonRow> devises = [], sessions = [], mouvements = [];
  JsonRow? current;

  DataService get data => widget.data;
  bool get isOpen => current?['statut'] == 'ouverte';

  @override
  void initState() {
    super.initState();
    _load();
  }

  num _toUsd(Object? montant, Object? deviseId) {
    final d = devises.where((x) => '${x['id']}' == '$deviseId').firstOrNull;
    final taux = (d?['taux'] as num?) ?? 1;
    return ((montant as num?) ?? 0) / (taux == 0 ? 1 : taux);
  }

  num get entrees =>
      mouvements.where((m) => m['sens'] == 'entree').fold(0, (s, m) => s + _toUsd(m['montant'], m['devise_id']));
  num get sorties =>
      mouvements.where((m) => m['sens'] == 'sortie').fold(0, (s, m) => s + _toUsd(m['montant'], m['devise_id']));
  num get ouverture => (current?['solde_ouverture'] as num?) ?? 0;
  num get theorique => ouverture + entrees - sorties;

  Future<void> _load({Object? keepId}) async {
    setState(() => loading = true);
    final r = await Future.wait([
      data.select('devises', const Query(eq: {'actif': true}, orderBy: 'id')),
      data.select('caisse_sessions', const Query(embed: ['users(nom)'], orderBy: 'jour', ascending: false, limit: 60)),
    ]);
    devises = r[0].data ?? [];
    sessions = r[1].data ?? [];
    error = r[1].error ?? r[0].error;
    final keep = keepId ?? current?['id'];
    current =
        sessions.where((s) => s['id'] == keep).firstOrNull ??
        sessions.where((s) => s['statut'] == 'ouverte').firstOrNull ??
        sessions.firstOrNull;
    await _loadMouvements();
  }

  Future<void> _loadMouvements() async {
    if (current == null) {
      mouvements = [];
    } else {
      final r = await data.select(
        'mouvements_caisse',
        Query(embed: const ['devises(code)'], eq: {'session_id': current!['id']}, orderBy: 'cree_le', ascending: false),
      );
      mouvements = r.data ?? [];
      error ??= r.error;
    }
    if (mounted) setState(() => loading = false);
  }

  // ---------------------------------------------------------------- actions
  Future<void> _openSession() async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _OpenSessionDialog(data: data, profile: widget.profile, sessions: sessions),
    );
    if (res == null || !mounted) return;
    toast(context, 'Session ouverte${savedSuffix(res.offline)}');
    _load(keepId: res.data!['id']);
  }

  Future<void> _newMouvement() async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _MouvementDialog(data: data, profile: widget.profile, session: current!, devises: devises),
    );
    if (res == null || !mounted) return;
    toast(context, '${res.data!['sens'] == 'entree' ? 'Entrée' : 'Sortie'} enregistrée${savedSuffix(res.offline)}');
    setState(() => loading = true);
    _loadMouvements();
  }

  Future<void> _close() async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _CloseDialog(data: data, session: current!, theorique: theorique),
    );
    if (res == null || !mounted) return;
    toast(context, 'Session clôturée${savedSuffix(res.offline)}');
    _load();
  }

  // ---------------------------------------------------------------- écran
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Caisse',
          subtitle: 'Une session par jour et par agent. Totaux en USD (CDF converti au taux de la table devises).',
          actions: [
            OutlinedButton.icon(
              onPressed: loading ? null : _openSession,
              icon: const Icon(Icons.lock_open, size: 18),
              label: const Text('Ouvrir une session'),
            ),
            FilledButton.icon(
              onPressed: isOpen && !loading ? _newMouvement : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Mouvement'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 420,
              child: DropdownButtonFormField<Object?>(
                key: ValueKey('sess-${current?['id']}-${sessions.length}'),
                initialValue: current?['id'],
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Session'),
                hint: const Text('Aucune session — ouvre-en une'),
                items: [
                  for (final s in sessions)
                    DropdownMenuItem(
                      value: s['id'],
                      child: Text(
                        overflow: TextOverflow.ellipsis,
                        '${_jour(s['jour'])} · ${(s['users'] as Map?)?['nom'] ?? 'Sans agent'}'
                        '${s['statut'] == 'cloturee' ? ' · clôturée' : ''}',
                      ),
                    ),
                ],
                onChanged: (id) {
                  setState(() {
                    current = sessions.firstWhere((s) => s['id'] == id);
                    loading = true;
                  });
                  _loadMouvements();
                },
              ),
            ),
            if (current != null) Pill(isOpen ? 'Ouverte' : 'Clôturée', isOpen ? Elk.ok : Theme.of(context).hintColor),
            if (isOpen)
              OutlinedButton.icon(
                onPressed: loading ? null : _close,
                icon: const Icon(Icons.lock, size: 18),
                label: const Text('Clôturer'),
              ),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            Kpi('Solde d’ouverture', _usd(ouverture)),
            Kpi('Entrées', _usd(entrees)),
            Kpi('Sorties', _usd(sorties)),
            Kpi('Solde théorique', _usd(theorique)),
          ],
        ),
        if (current?['statut'] == 'cloturee' && current?['solde_cloture'] != null) ...[
          const SizedBox(height: 16),
          _EcartCard(compte: current!['solde_cloture'] as num, theorique: theorique),
        ],
        const SizedBox(height: 16),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Erreur : $error', style: const TextStyle(color: Elk.crit)),
          ),
        TableCard(
          loading: loading,
          empty: current == null
              ? 'Aucune session de caisse. Clique « Ouvrir une session ».'
              : 'Aucun mouvement dans cette session.',
          columns: const [
            DataColumn(label: Text('Heure')),
            DataColumn(label: Text('Libellé')),
            DataColumn(label: Text('Module')),
            DataColumn(label: Text('Nature')),
            DataColumn(label: Text('Sens')),
            DataColumn(label: Text('Montant'), numeric: true),
          ],
          rows: [
            for (final m in mouvements)
              DataRow(
                cells: [
                  DataCell(Text(_heure(m['cree_le']))),
                  DataCell(Text('${m['libelle'] ?? ''}')),
                  DataCell(Text('${m['module'] ?? '—'}')),
                  DataCell(Text(_sources[m['source_type']] ?? '${m['source_type'] ?? '—'}')),
                  DataCell(m['sens'] == 'entree' ? const Pill('Entrée', Elk.ok) : const Pill('Sortie', Elk.crit)),
                  DataCell(
                    Text(
                      '${m['sens'] == 'entree' ? '+' : '−'} ${Elk.money(m['montant'], (m['devises'] as Map?)?['code'] as String?)}',
                      style: TextStyle(color: m['sens'] == 'entree' ? Elk.ok : Elk.crit, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static String _heure(Object? t) {
    final d = DateTime.tryParse('$t');
    return d == null ? '—' : DateFormat.Hm('fr_FR').format(d.toLocal());
  }
}

class _EcartCard extends StatelessWidget {
  const _EcartCard({required this.compte, required this.theorique});
  final num compte, theorique;
  @override
  Widget build(BuildContext context) {
    final diff = compte - theorique;
    final (label, color) = diff.abs() < 0.005
        ? ('Caisse juste', Elk.ok)
        : diff > 0
        ? ('Excédent', Elk.warn)
        : ('Manquant', Elk.crit);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Wrap(
          spacing: 18,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Clôture', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('Solde compté : ${_usd(compte)}'),
            Text('Écart : ${diff > 0 ? '+' : ''}${_usd(diff)}'),
            Pill(label, color),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ dialogues
class _OpenSessionDialog extends StatefulWidget {
  const _OpenSessionDialog({required this.data, required this.profile, required this.sessions});
  final DataService data;
  final Profile profile;
  final List<JsonRow> sessions;
  @override
  State<_OpenSessionDialog> createState() => _OpenSessionDialogState();
}

class _OpenSessionDialogState extends State<_OpenSessionDialog> {
  final _form = GlobalKey<FormState>();
  final _solde = TextEditingController();
  DateTime jour = DateTime.now();
  bool busy = false;
  String error = '';

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final j = DateFormat('yyyy-MM-dd').format(jour);
    // contrôle aussi fait ici : hors ligne, la base ne peut pas le vérifier
    if (widget.sessions.any((s) => s['jour'] == j && s['agent_id'] == widget.profile.userId)) {
      return setState(() => error = 'Une session existe déjà pour ce jour et cet agent.');
    }
    setState(() => busy = true);
    final res = await widget.data.insert('caisse_sessions', {
      'jour': j,
      'solde_ouverture': parseAmount(_solde.text),
      'agent_id': widget.profile.userId,
      'statut': 'ouverte',
    });
    if (!mounted) return;
    if (!res.ok) {
      return setState(() {
        busy = false;
        error = res.code == '23505' ? 'Une session existe déjà pour ce jour et cet agent.' : 'Erreur : ${res.error}';
      });
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ouvrir une session de caisse'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            formGrid([
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Jour'),
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: jour,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      locale: const Locale('fr', 'FR'),
                    );
                    if (d != null) setState(() => jour = d);
                  },
                  child: Text(DateFormat('EEEE d MMMM y', 'fr_FR').format(jour)),
                ),
              ),
              AmountField(controller: _solde, label: 'Solde d’ouverture (USD)', allowZero: true),
            ]),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error, style: const TextStyle(color: Elk.crit)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Ouverture…' : 'Ouvrir')),
    ],
  );
}

class _MouvementDialog extends StatefulWidget {
  const _MouvementDialog({required this.data, required this.profile, required this.session, required this.devises});
  final DataService data;
  final Profile profile;
  final JsonRow session;
  final List<JsonRow> devises;
  @override
  State<_MouvementDialog> createState() => _MouvementDialogState();
}

class _MouvementDialogState extends State<_MouvementDialog> {
  final _form = GlobalKey<FormState>();
  final _lib = TextEditingController();
  final _montant = TextEditingController();
  String sens = 'entree', module = _modules.first, source = 'paiement';
  late Object? devise = widget.devises.firstOrNull?['id'];
  bool busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final res = await widget.data.insert('mouvements_caisse', {
      'session_id': widget.session['id'],
      'sens': sens,
      'libelle': _lib.text.trim(),
      'module': module,
      'source_type': source,
      'montant': parseAmount(_montant.text),
      'devise_id': devise,
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
    title: const Text('Nouveau mouvement'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: formGrid([
          dropdown<String>('Sens', sens, const {'entree': 'Entrée', 'sortie': 'Sortie'}, (v) => sens = v ?? sens),
          TextFormField(
            controller: _lib,
            decoration: const InputDecoration(labelText: 'Libellé', hintText: 'Ex. Billet ELK-2041, carburant…'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Libellé requis' : null,
          ),
          dropdown<String>('Module', module, {for (final m in _modules) m: m}, (v) => module = v ?? module),
          dropdown<String>('Nature', source, _sources, (v) => source = v ?? source),
          AmountField(controller: _montant, label: 'Montant'),
          dropdown<Object?>('Devise', devise, {
            for (final d in widget.devises) d['id']: '${d['code']}',
          }, (v) => devise = v),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer')),
    ],
  );
}

class _CloseDialog extends StatefulWidget {
  const _CloseDialog({required this.data, required this.session, required this.theorique});
  final DataService data;
  final JsonRow session;
  final num theorique;
  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  final _form = GlobalKey<FormState>();
  late final _compte = TextEditingController(text: ((widget.theorique * 100).round() / 100).toString());
  bool busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final res = await widget.data.update('caisse_sessions', widget.session['id'] as Object, {
      'solde_cloture': parseAmount(_compte.text),
      'statut': 'cloturee',
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
    title: Text('Clôturer la session du ${_jour(widget.session['jour'])}'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saisis le solde réellement compté. L’écart avec le solde théorique est conservé pour le suivi. '
              'Plus aucun mouvement ne pourra être ajouté ensuite.',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 14),
            formGrid([
              AmountField(controller: _compte, label: 'Solde compté (USD)', allowZero: true),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Solde théorique (USD)'),
                child: Text(_usd(widget.theorique)),
              ),
            ]),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Clôture…' : 'Clôturer')),
    ],
  );
}
