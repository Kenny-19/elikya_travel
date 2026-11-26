// Module Caisse — en langage de tous les jours, pour quelqu'un qui n'est pas à l'aise avec l'ordinateur :
//   le matin  : « Ouvrir ma caisse » (on compte l'argent du départ) ;
//   la journée : un grand chiffre « En caisse maintenant » + deux gros boutons
//                « Argent reçu » / « Argent sorti » avec des choix tout faits ;
//   le soir   : « Fermer ma caisse » (on compte ; l'écran dit tout de suite s'il manque de l'argent).
// Suivi uniquement : on NOTE les mouvements, aucun traitement d'argent. Totaux en USD
// (CDF converti au taux de la table devises). Une caisse par agent et par jour.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/location_logic.dart' show jourCle;
import '../../data/remote.dart';
import '../../profile.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets.dart';

String _usd(num n) => Elk.money((n * 100).round() / 100, 'USD');
num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
String _jourLong(Object? j) {
  final d = DateTime.tryParse('$j');
  if (d == null) return '$j';
  final s = DateFormat('EEEE d MMMM', 'fr_FR').format(d);
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Choix tout faits pour « Argent reçu » / « Argent sorti » : (libellé, module, type de source).
const choixEntree = [
  ('Billet d’avion', 'Voyage'),
  ('Visa', 'Voyage'),
  ('Hôtel / assurance', 'Voyage'),
  ('Location de véhicule', 'Location'),
  ('Vente fourniture', 'Fourniture'),
  ('Mobile money', 'Mobile money'),
  ('Autre', 'Autre'),
];
const choixSortie = [
  ('Carburant', 'Logistique'),
  ('Transport', 'Logistique'),
  ('Achat de fournitures', 'Fourniture'),
  ('Paiement fournisseur', 'Admin'),
  ('Petites dépenses', 'Admin'),
  ('Dépôt à la banque', 'Admin'),
  ('Autre', 'Autre'),
];

/// Écart entre l'argent compté et ce qui devrait être en caisse : (texte, couleur).
(String, Color) ecartTexte(num compte, num theorique) {
  final d = ((compte - theorique) * 100).round() / 100;
  if (d.abs() < 0.01) return ('C’est juste ✓', Elk.ok);
  return d < 0 ? ('Il manque ${_usd(-d)}', Elk.crit) : ('Il y a ${_usd(d)} de trop', Elk.warn);
}

class CaissePage extends StatefulWidget {
  const CaissePage({super.key, required this.data, required this.profile});
  final DataService data;
  final Profile profile;
  @override
  State<CaissePage> createState() => _CaissePageState();
}

class _CaissePageState extends State<CaissePage> with AutoRafraichi {
  @override
  void rafraichir() => _load(silencieux: true); // mise à jour automatique (navigation.dart)

  bool loading = true, histo = false;
  String? error;
  List<JsonRow> devises = [], sessions = [], mouvements = [];
  final _ouverture = TextEditingController();

  DataService get data => widget.data;
  String get today => jourCle(DateTime.now());

  /// Ma caisse d'aujourd'hui (ouverte ou déjà fermée), s'il y en a une.
  JsonRow? get maCaisse =>
      sessions.where((s) => s['jour'] == today && '${s['agent_id']}' == '${widget.profile.userId}').firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silencieux = false}) async {
    if (!silencieux) setState(() => loading = true);
    final depuis = jourCle(DateTime.now().subtract(const Duration(days: 30)));
    final r = await Future.wait([
      data.select('devises', const Query(orderBy: 'id')),
      data.select(
        'caisse_sessions',
        Query(embed: const ['users(nom)'], gte: {'jour': depuis}, orderBy: 'jour', ascending: false),
      ),
      data.select(
        'mouvements_caisse',
        Query(gte: {'cree_le': DateTime.parse(depuis).toUtc().toIso8601String()}, orderBy: 'cree_le', ascending: false),
      ),
    ]);
    if (!mounted) return;
    setState(() {
      devises = r[0].data ?? [];
      sessions = r[1].data ?? [];
      mouvements = r[2].data ?? [];
      error = r.map((x) => x.error).whereType<String>().firstOrNull;
      loading = false;
    });
    Navigation.prendreAction('caisse'); // « Ouvrir ma caisse » : l'écran affiche déjà le bon bouton
  }

  num _toUsd(Object? montant, Object? deviseId) {
    final t = _num(devises.where((x) => '${x['id']}' == '$deviseId').firstOrNull?['taux']);
    return _num(montant) / (t == 0 ? 1 : t);
  }

  List<JsonRow> _mvts(JsonRow s) => mouvements.where((m) => '${m['session_id']}' == '${s['id']}').toList();
  num _entrees(JsonRow s) =>
      _mvts(s).where((m) => m['sens'] == 'entree').fold<num>(0, (a, m) => a + _toUsd(m['montant'], m['devise_id']));
  num _sorties(JsonRow s) =>
      _mvts(s).where((m) => m['sens'] == 'sortie').fold<num>(0, (a, m) => a + _toUsd(m['montant'], m['devise_id']));
  num _theorique(JsonRow s) => _num(s['solde_ouverture']) + _entrees(s) - _sorties(s);
  String _code(Object? id) => '${devises.where((x) => '${x['id']}' == '$id').firstOrNull?['code'] ?? 'USD'}';

  // ---------------------------------------------------------------- actions
  Future<void> _ouvrir() async {
    final v = parseAmount(_ouverture.text);
    if (v == null || v < 0) return toast(context, 'Indiquez l’argent présent dans la caisse (0 si elle est vide).');
    final res = await data.insert('caisse_sessions', {
      'jour': today,
      'solde_ouverture': v,
      'agent_id': widget.profile.userId,
      'statut': 'ouverte',
    });
    if (!mounted) return;
    if (!res.ok) {
      return toast(
        context,
        res.code == '23505' ? 'Votre caisse est déjà ouverte aujourd’hui.' : 'Erreur : ${res.error}',
      );
    }
    _ouverture.clear();
    toast(context, 'Caisse ouverte${savedSuffix(res.offline)}');
    _load();
  }

  Future<void> _mouvement(String sens) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) =>
          _MouvementDialog(data: data, profile: widget.profile, session: maCaisse!, devises: devises, sens: sens),
    );
    if (res == null || !mounted) return;
    toast(context, '${sens == 'entree' ? 'Argent reçu' : 'Argent sorti'} noté${savedSuffix(res.offline)}');
    _load();
  }

  Future<void> _fermer() async {
    final s = maCaisse!;
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _FermerDialog(data: data, session: s, theorique: _theorique(s)),
    );
    if (res == null || !mounted) return;
    toast(context, 'Caisse fermée${savedSuffix(res.offline)}');
    _load();
  }

  // ---------------------------------------------------------------- écran
  @override
  Widget build(BuildContext context) {
    final s = maCaisse, muted = Theme.of(context).hintColor;
    final passees = sessions.where((x) => x != s).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Ma caisse',
          subtitle: 'Notez ici chaque fois que de l’argent entre ou sort de la caisse.',
          actions: [
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (error != null) Text('Erreur : $error', style: const TextStyle(color: Elk.crit)),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.profile.userId == null)
          const EtatVide(
            icone: Icons.person_off_outlined,
            texte: 'Votre compte n’est pas relié à une fiche employé : demandez à la direction.',
          )
        else if (s == null)
          _carteOuvrir()
        else if (s['statut'] == 'cloturee')
          _carteFermee(s)
        else
          ..._caisseOuverte(s, muted),
        const SizedBox(height: 26),
        if (passees.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() => histo = !histo),
            icon: Icon(histo ? Icons.expand_less : Icons.expand_more),
            label: Text(histo ? 'Masquer les jours précédents' : 'Voir les jours précédents (${passees.length})'),
          ),
        if (histo)
          for (final x in passees)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  '${_jourLong(x['jour'])} · ${(x['users'] as Map?)?['nom'] ?? 'Sans agent'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Départ ${_usd(_num(x['solde_ouverture']))} · reçu ${_usd(_entrees(x))} · sorti ${_usd(_sorties(x))}',
                ),
                trailing: x['statut'] == 'cloturee' && x['solde_cloture'] != null
                    ? Pill(
                        ecartTexte(_num(x['solde_cloture']), _theorique(x)).$1,
                        ecartTexte(_num(x['solde_cloture']), _theorique(x)).$2,
                      )
                    : const Pill('Pas fermée', Elk.warn),
              ),
            ),
      ],
    );
  }

  Widget _carteOuvrir() => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_open, color: Elk.navy2, size: 30),
              SizedBox(width: 12),
              Text(
                'Votre caisse n’est pas encore ouverte',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Comptez l’argent qui est dans la caisse ce matin, puis indiquez le montant.',
            style: TextStyle(fontSize: 15, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _ouverture,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    labelText: 'Argent dans la caisse (USD)',
                    suffixText: '\$',
                    hintText: '0',
                  ),
                  onSubmitted: (_) => _ouvrir(),
                ),
              ),
              FilledButton.icon(
                onPressed: _ouvrir,
                icon: const Icon(Icons.lock_open),
                label: const Text('Ouvrir ma caisse'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _carteFermee(JsonRow s) {
    final (texte, couleur) = ecartTexte(_num(s['solde_cloture']), _theorique(s));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(Icons.lock, color: couleur, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Caisse fermée pour aujourd’hui',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Compté le soir : ${_usd(_num(s['solde_cloture']))} · attendu : ${_usd(_theorique(s))}',
                    style: TextStyle(fontSize: 15, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            Pill(texte, couleur),
          ],
        ),
      ),
    );
  }

  List<Widget> _caisseOuverte(JsonRow s, Color muted) {
    final mvts = _mvts(s);
    return [
      // le grand chiffre
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 30,
            runSpacing: 18,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'En caisse maintenant',
                    style: TextStyle(fontSize: 15, color: muted, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _usd(_theorique(s)),
                    style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1),
                  ),
                  Text(
                    'Départ ${_usd(_num(s['solde_ouverture']))} · reçu + ${_usd(_entrees(s))} · sorti − ${_usd(_sorties(s))}',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    height: 64,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Elk.ok,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontFamily: Elk.font, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => _mouvement('entree'),
                      icon: const Icon(Icons.add_circle_outline, size: 26),
                      label: const Text('Argent reçu'),
                    ),
                  ),
                  SizedBox(
                    height: 64,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Elk.crit,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontFamily: Elk.font, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      onPressed: () => _mouvement('sortie'),
                      icon: const Icon(Icons.remove_circle_outline, size: 26),
                      label: const Text('Argent sorti'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      const TitreSection('Aujourd’hui'),
      const SizedBox(height: 8),
      if (mvts.isEmpty)
        const EtatVide(icone: Icons.receipt_long_outlined, texte: 'Rien de noté pour l’instant aujourd’hui.')
      else
        for (final m in mvts)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                m['sens'] == 'entree' ? Icons.south_west : Icons.north_east,
                color: m['sens'] == 'entree' ? Elk.ok : Elk.crit,
              ),
              title: Text('${m['libelle'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                m['cree_le'] == null ? '' : DateFormat.Hm('fr_FR').format(DateTime.parse('${m['cree_le']}').toLocal()),
              ),
              trailing: Text(
                '${m['sens'] == 'entree' ? '+' : '−'} ${Elk.money(m['montant'], _code(m['devise_id']))}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: m['sens'] == 'entree' ? Elk.ok : Elk.crit,
                ),
              ),
            ),
          ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _fermer,
          icon: const Icon(Icons.lock),
          label: const Text('Fermer ma caisse (fin de journée)'),
        ),
      ),
    ];
  }
}

// ------------------------------------------------------------------ argent reçu / sorti
class _MouvementDialog extends StatefulWidget {
  const _MouvementDialog({
    required this.data,
    required this.profile,
    required this.session,
    required this.devises,
    required this.sens,
  });
  final DataService data;
  final Profile profile;
  final JsonRow session;
  final List<JsonRow> devises;
  final String sens; // entree | sortie
  @override
  State<_MouvementDialog> createState() => _MouvementDialogState();
}

class _MouvementDialogState extends State<_MouvementDialog> {
  final _form = GlobalKey<FormState>();
  final _montant = TextEditingController();
  final _detail = TextEditingController();
  (String, String)? choix;
  late Object? devise =
      (widget.devises.where((x) => x['code'] == 'USD').firstOrNull ?? widget.devises.firstOrNull)?['id'];
  bool busy = false;

  bool get entree => widget.sens == 'entree';

  Future<void> _save() async {
    if (choix == null) {
      return toast(context, entree ? 'Choisissez d’où vient l’argent.' : 'Choisissez pour quoi l’argent est sorti.');
    }
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final detail = _detail.text.trim();
    final res = await widget.data.insert('mouvements_caisse', {
      'session_id': widget.session['id'],
      'sens': widget.sens,
      'libelle': detail.isEmpty ? choix!.$1 : '${choix!.$1} · $detail',
      'module': choix!.$2,
      'source_type': entree ? 'paiement' : 'depense',
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
    title: Row(
      children: [
        Icon(
          entree ? Icons.add_circle_outline : Icons.remove_circle_outline,
          color: entree ? Elk.ok : Elk.crit,
          size: 28,
        ),
        const SizedBox(width: 10),
        Text(entree ? 'Argent reçu' : 'Argent sorti'),
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
            Etape('1', entree ? 'D’où vient cet argent ?' : 'Pour quoi ?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in entree ? choixEntree : choixSortie)
                  ChoiceChip(
                    label: Text(c.$1),
                    selected: choix == c,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => choix = c),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Etape('2', 'Combien ?'),
            formGrid([
              TextFormField(
                controller: _montant,
                autofocus: true,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(labelText: 'Montant'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (parseAmount(v) ?? 0) > 0 ? null : 'Indiquez le montant',
              ),
              dropdown<Object?>('Devise', devise, {
                for (final x in widget.devises) x['id']: '${x['code']}',
              }, (v) => setState(() => devise = v)),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _detail,
              decoration: InputDecoration(
                labelText: entree ? 'Détail : nom du client, n° de dossier… (facultatif)' : 'Détail (facultatif)',
              ),
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

// ------------------------------------------------------------------ fermer la caisse
class _FermerDialog extends StatefulWidget {
  const _FermerDialog({required this.data, required this.session, required this.theorique});
  final DataService data;
  final JsonRow session;
  final num theorique;
  @override
  State<_FermerDialog> createState() => _FermerDialogState();
}

class _FermerDialogState extends State<_FermerDialog> {
  final _compte = TextEditingController();
  bool busy = false;

  Future<void> _save() async {
    final v = parseAmount(_compte.text);
    if (v == null || v < 0) return toast(context, 'Indiquez l’argent compté dans la caisse.');
    setState(() => busy = true);
    final res = await widget.data.update('caisse_sessions', widget.session['id'] as Object, {
      'solde_cloture': v,
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
  Widget build(BuildContext context) {
    final v = parseAmount(_compte.text);
    final ecart = v == null ? null : ecartTexte(v, widget.theorique);
    return AlertDialog(
      title: const Text('Fermer ma caisse'),
      content: SizedBox(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Comptez tout l’argent qui est dans la caisse, puis indiquez le montant.',
              style: TextStyle(fontSize: 15, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _compte,
              autofocus: true,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Argent compté (USD)', suffixText: '\$'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              'Selon vos notes, il devrait y avoir ${_usd(widget.theorique)}.',
              style: const TextStyle(fontSize: 15),
            ),
            if (ecart != null) ...[
              const SizedBox(height: 10),
              Text(
                ecart.$1,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ecart.$2),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Après la fermeture, on ne peut plus rien ajouter pour aujourd’hui.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Fermeture…' : 'Fermer ma caisse')),
      ],
    );
  }
}
