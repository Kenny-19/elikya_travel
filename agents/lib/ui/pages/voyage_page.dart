// Module Voyage — billets, visas, hôtels, assurances, packages. Pensé pour être TRÈS simple :
// - une ligne par dossier : qui, où, quand, et surtout « payé / reste à payer » (barre) ;
// - un gros bouton « Encaisser » tant qu'il reste à payer ; « Passer à : Déposé » pour un visa ;
// - nouveau dossier en 4 étapes ; les champs affichés dépendent du service choisi ;
// - alerte en tête : départs dans 3 jours pas encore soldés, avec le téléphone du client.
// Règles (paiement, avancement, visa) : lib/data/voyage_logic.dart (testées).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/location_logic.dart' show jourCle;
import '../../data/remote.dart';
import '../../data/voyage_logic.dart';
import '../../profile.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets.dart';

num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

/// 320.0 → « 320 », 99.5 → « 99.5 » (montant proposé dans un champ).
String _texteMontant(num n) => n == n.roundToDouble() ? '${n.round()}' : '${(n * 100).round() / 100}';
String _date(Object? k) =>
    k == null || '$k'.isEmpty ? '' : DateFormat('EEE d MMM', 'fr_FR').format(DateTime.parse('$k'));

const _icones = {
  'billet': Icons.flight_takeoff,
  'visa': Icons.badge_outlined,
  'hotel': Icons.hotel_outlined,
  'assurance': Icons.health_and_safety_outlined,
  'package': Icons.card_travel,
};
const _modes = {'especes': 'Espèces', 'mobile_money': 'Mobile money', 'banque': 'Banque'};

Color _couleurPaiement(String code) => switch (code) {
  'solde' || 'trop_percu' => Elk.ok,
  'acompte' => Elk.warn,
  'non_paye' => Elk.crit,
  _ => Elk.slate,
};
Color _couleurAvancement(String a) => switch (a) {
  'devis' => Elk.info,
  'confirme' => Elk.navy2,
  'termine' => Elk.ok,
  _ => Elk.slate,
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
  List<JsonRow> dossiers = [], paiements = [], clients = [], devises = [];
  JsonRow? maCaisse; // session de caisse ouverte de l'agent aujourd'hui (pour « ajouter à ma caisse »)
  String filtre = 'actifs', recherche = '';

  DataService get data => widget.data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final r = await Future.wait([
      data.select(
        'dossiers',
        const Query(
          embed: ['clients(nom,telephone)', 'devises(code)'],
          orderBy: 'cree_le',
          ascending: false,
          limit: 800,
        ),
      ),
      data.select('paiements', const Query(eq: {'source_type': 'dossier'}, orderBy: 'cree_le', limit: 3000)),
      data.select('clients', const Query(orderBy: 'nom')),
      data.select('devises', const Query(orderBy: 'id')),
      if (widget.profile.can('caisse') && widget.profile.userId != null)
        data.select(
          'caisse_sessions',
          Query(eq: {'statut': 'ouverte', 'agent_id': widget.profile.userId, 'jour': jourCle(DateTime.now())}),
        ),
    ]);
    if (!mounted) return;
    setState(() {
      dossiers = r[0].data ?? [];
      paiements = r[1].data ?? [];
      clients = r[2].data ?? [];
      devises = r[3].data ?? [];
      maCaisse = r.length > 4 ? r[4].data?.firstOrNull : null;
      error = r.map((x) => x.error).whereType<String>().firstOrNull;
      loading = false;
    });
    // bouton de l'accueil
    final action = Navigation.prendreAction('voyage');
    if (action == 'nouveau') _dossier();
    if (action == 'non_soldes') setState(() => filtre = 'non_soldes');
  }

  EtatPaiement _paiement(JsonRow d) => etatPaiement(d, paiementsDe(paiements, d['id']), devises);
  String _code(Object? deviseId) =>
      '${devises.where((x) => '${x['id']}' == '$deviseId').firstOrNull?['code'] ?? 'USD'}';
  String _argent(num n, Object? deviseId) => Elk.money((n * 100).round() / 100, _code(deviseId));

  // ---------------------------------------------------------------- actions
  Future<void> _dossier([JsonRow? d]) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _DossierDialog(
        data: data,
        profile: widget.profile,
        clients: clients,
        devises: devises,
        dossier: d,
        maCaisse: maCaisse,
      ),
    );
    if (res == null || !mounted) return;
    toast(context, 'Dossier ${res.data?['ref'] ?? ''} enregistré${savedSuffix(res.offline)}');
    _load();
  }

  Future<void> _encaisser(JsonRow d) async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) => _EncaisserDialog(
        data: data,
        profile: widget.profile,
        dossier: d,
        devises: devises,
        paiements: paiementsDe(paiements, d['id']),
        etat: _paiement(d),
        maCaisse: maCaisse,
      ),
    );
    if (res == null || !mounted) return;
    toast(context, res);
    _load();
  }

  Future<void> _maj(JsonRow d, JsonRow patch, String message) async {
    final res = await data.update('dossiers', d['id'] as Object, patch);
    if (!mounted) return;
    toast(context, res.ok ? '$message${savedSuffix(res.offline)}' : 'Erreur : ${res.error}');
    _load();
  }

  Future<void> _annuler(JsonRow d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Annuler ce dossier ?'),
        content: Text(
          '${d['ref']} · ${(d['clients'] as Map?)?['nom'] ?? ''}\nLes encaissements déjà enregistrés restent visibles.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non, garder')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Elk.crit, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (ok == true) _maj(d, {'statut': 'annule'}, 'Dossier annulé');
  }

  // ---------------------------------------------------------------- écran
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final etats = {for (final d in dossiers) d['id']: _paiement(d)};
    final actifs = dossiers.where((d) => {'devis', 'confirme'}.contains(avancement(d))).toList();
    final urgents = actifs.where((d) => departProcheNonSolde(d, etats[d['id']]!, now)).toList();
    final departs7 = actifs.where((d) {
      final n = joursAvantDepart(d, now);
      return n != null && n >= 0 && n <= 7;
    }).length;
    final visas = actifs.where((d) => d['type'] == 'visa' && !{'obtenu', 'refuse'}.contains(d['etape_visa'])).length;
    num reste = 0;
    for (final d in actifs) {
      reste += convertir(etats[d['id']]!.reste, d['devise_id'], 1, devises);
    }

    final q = recherche.trim().toLowerCase();
    final liste = dossiers.where((d) {
      final a = avancement(d), p = etats[d['id']]!;
      final ok = switch (filtre) {
        'actifs' => a == 'devis' || a == 'confirme',
        'non_soldes' => a != 'annule' && p.reste > 0,
        'visas' => d['type'] == 'visa' && a != 'annule',
        'archives' => a == 'termine' || a == 'annule',
        _ => true,
      };
      if (!ok) return false;
      if (q.isEmpty) return true;
      return [
        d['ref'],
        (d['clients'] as Map?)?['nom'],
        d['destination'],
        d['pays'],
        d['hotel'],
        d['passager'],
        d['reference'],
      ].any((x) => '${x ?? ''}'.toLowerCase().contains(q));
    }).toList();
    if (filtre == 'actifs') {
      // à venir d'abord (date de départ la plus proche), puis sans date
      liste.sort((a, b) => '${a['date_depart'] ?? '9999'}'.compareTo('${b['date_depart'] ?? '9999'}'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Voyage',
          subtitle: 'Billets, visas, hôtels, assurances. Cliquez « Encaisser » quand le client paie.',
          actions: [
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
            FilledButton.icon(
              onPressed: loading ? null : () => _dossier(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nouveau dossier'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Compteur(
              Icons.folder_open,
              Elk.navy2,
              '${actifs.length}',
              actifs.length > 1 ? 'dossiers en cours' : 'dossier en cours',
            ),
            if (departs7 > 0) Compteur(Icons.flight_takeoff, Elk.info, '$departs7', 'départ(s) dans 7 jours'),
            if (reste > 0)
              Compteur(
                Icons.payments_outlined,
                Elk.warn,
                Elk.money((reste * 100).round() / 100, 'USD'),
                'reste à encaisser',
              ),
            if (visas > 0) Compteur(Icons.badge_outlined, Elk.navy2, '$visas', 'visa(s) en cours'),
          ],
        ),
        if (urgents.isNotEmpty) ...[
          const SizedBox(height: 14),
          Bandeau(
            couleur: Elk.crit,
            icone: Icons.warning_amber_rounded,
            texte: urgents.length == 1
                ? '1 client part bientôt et n’a pas tout payé.'
                : '${urgents.length} clients partent bientôt et n’ont pas tout payé.',
            details: [
              for (final d in urgents)
                '${(d['clients'] as Map?)?['nom'] ?? ''} ${(d['clients'] as Map?)?['telephone'] ?? ''} · départ ${_date(d['date_depart'])} · '
                    'reste ${_argent(etats[d['id']]!.reste, d['devise_id'])}',
            ],
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Erreur : $error', style: const TextStyle(color: Elk.crit)),
          ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in const [
              ('actifs', 'En cours'),
              ('non_soldes', 'Pas soldés'),
              ('visas', 'Visas'),
              ('archives', 'Effectués / annulés'),
              ('tous', 'Tous'),
            ])
              ChoiceChip(label: Text(f.$2), selected: filtre == f.$1, onSelected: (_) => setState(() => filtre = f.$1)),
            const SizedBox(width: 8),
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Rechercher (client, réf., destination…)',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => recherche = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (liste.isEmpty)
          EtatVide(
            icone: Icons.luggage_outlined,
            texte: dossiers.isEmpty ? 'Aucun dossier pour l’instant.' : 'Aucun dossier dans cette liste.',
            bouton: dossiers.isEmpty
                ? FilledButton.icon(
                    onPressed: () => _dossier(),
                    icon: const Icon(Icons.add),
                    label: const Text('Créer le premier dossier'),
                  )
                : null,
          )
        else
          for (final d in liste)
            _LigneDossier(
              dossier: d,
              paiement: etats[d['id']]!,
              argent: (n) => _argent(n, d['devise_id']),
              onEncaisser: () => _encaisser(d),
              onModifier: () => _dossier(d),
              onAnnuler: () => _annuler(d),
              onMaj: (patch, msg) => _maj(d, patch, msg),
            ),
      ],
    );
  }
}

/// Une ligne de dossier : qui / où / quand + barre « payé / reste » + UN bouton principal.
class _LigneDossier extends StatelessWidget {
  const _LigneDossier({
    required this.dossier,
    required this.paiement,
    required this.argent,
    required this.onEncaisser,
    required this.onModifier,
    required this.onAnnuler,
    required this.onMaj,
  });
  final JsonRow dossier;
  final EtatPaiement paiement;
  final String Function(num) argent;
  final VoidCallback onEncaisser, onModifier, onAnnuler;
  final void Function(JsonRow patch, String message) onMaj;

  String _details() {
    final d = dossier;
    final parts = <String>[];
    switch (d['type']) {
      case 'visa':
        // le pays est déjà dans le titre de la ligne
        parts.add(etapesVisa[d['etape_visa'] ?? 'a_deposer']!);
        if (d['date_depart'] != null) parts.add('voyage prévu ${_date(d['date_depart'])}');
      case 'hotel':
        if (d['hotel'] != null) parts.add('${d['hotel']}');
        if (d['date_depart'] != null) {
          parts.add('du ${_date(d['date_depart'])}${d['date_retour'] != null ? ' au ${_date(d['date_retour'])}' : ''}');
        }
      default:
        if (d['date_depart'] != null) {
          parts.add(
            'départ ${_date(d['date_depart'])}${d['date_retour'] != null ? ' · retour ${_date(d['date_retour'])}' : (d['type'] == 'billet' ? ' · aller simple' : '')}',
          );
        }
        if (d['compagnie'] != null) parts.add('${d['compagnie']}');
    }
    if (d['reference'] != null) parts.add('réf. ${d['reference']}');
    if (d['passager'] != null) parts.add('voyageur : ${d['passager']}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final d = dossier, a = avancement(d), p = paiement, muted = Theme.of(context).hintColor;
    final total = _num(d['montant']);
    final ou = d['type'] == 'visa' ? (d['pays'] ?? d['destination']) : (d['destination'] ?? d['hotel']);
    final suivante = d['type'] == 'visa' && a != 'annule' ? etapeVisaSuivante(d['etape_visa'] as String?) : null;
    final enTraitement = d['type'] == 'visa' && d['etape_visa'] == 'en_traitement' && a != 'annule';

    final Widget? principal = a == 'annule'
        ? null
        : p.reste > 0
        ? FilledButton.icon(
            onPressed: onEncaisser,
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Encaisser'),
          )
        : suivante != null
        ? OutlinedButton(
            onPressed: () => onMaj({'etape_visa': suivante}, 'Visa : ${etapesVisa[suivante]}'),
            child: Text('Passer à : ${etapesVisa[suivante]}'),
          )
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: Elk.navy.withValues(alpha: .07),
              child: Icon(_icones[d['type']] ?? Icons.luggage_outlined, color: Elk.navy2),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${(d['clients'] as Map?)?['nom'] ?? '—'}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        if (ou != null)
                          TextSpan(
                            text: '  →  $ou',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${typesDossier[d['type']] ?? d['type']} · ${d['ref'] ?? ''}${_details().isEmpty ? '' : ' · ${_details()}'}',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      Pill(libellesAvancement[a]!, _couleurAvancement(a)),
                      if (p.code != 'sans_montant') Pill(p.libelle, _couleurPaiement(p.code)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // paiement : total + barre + reste
            SizedBox(
              width: 190,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    total > 0 ? argent(total) : '—',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (p.paye / total).clamp(0, 1).toDouble(),
                        minHeight: 7,
                        backgroundColor: Elk.mist,
                        color: _couleurPaiement(p.code),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.reste > 0 ? 'Payé ${argent(p.paye)} · reste ${argent(p.reste)}' : 'Tout est payé',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 230,
              child: Align(alignment: Alignment.centerRight, child: principal ?? const SizedBox.shrink()),
            ),
            PopupMenuButton<String>(
              tooltip: 'Plus',
              onSelected: (c) => switch (c) {
                'modifier' => onModifier(),
                'confirme' => onMaj({'statut': 'confirme'}, 'Dossier confirmé'),
                'termine' => onMaj({'statut': 'termine'}, 'Voyage marqué comme effectué'),
                'obtenu' => onMaj({'etape_visa': 'obtenu'}, 'Visa obtenu 🎉'),
                'refuse' => onMaj({'etape_visa': 'refuse'}, 'Visa refusé'),
                'encaisser' => onEncaisser(),
                'annuler' => onAnnuler(),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'modifier', child: Text('Modifier le dossier')),
                if (a != 'annule')
                  const PopupMenuItem(value: 'encaisser', child: Text('Encaisser / voir les paiements')),
                if (a == 'devis') const PopupMenuItem(value: 'confirme', child: Text('Le client confirme')),
                if (enTraitement) const PopupMenuItem(value: 'obtenu', child: Text('Visa obtenu')),
                if (enTraitement) const PopupMenuItem(value: 'refuse', child: Text('Visa refusé')),
                if (a == 'confirme') const PopupMenuItem(value: 'termine', child: Text('Voyage effectué')),
                if (a != 'annule' && a != 'termine')
                  const PopupMenuItem(value: 'annuler', child: Text('Annuler le dossier')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ encaisser
class _EncaisserDialog extends StatefulWidget {
  const _EncaisserDialog({
    required this.data,
    required this.profile,
    required this.dossier,
    required this.devises,
    required this.paiements,
    required this.etat,
    this.maCaisse,
  });
  final DataService data;
  final Profile profile;
  final JsonRow dossier;
  final List<JsonRow> devises, paiements;
  final EtatPaiement etat;
  final JsonRow? maCaisse;
  @override
  State<_EncaisserDialog> createState() => _EncaisserDialogState();
}

class _EncaisserDialogState extends State<_EncaisserDialog> {
  final _form = GlobalKey<FormState>();
  late final _montant = TextEditingController(text: widget.etat.reste > 0 ? _texteMontant(widget.etat.reste) : '');
  final _ref = TextEditingController();
  String mode = 'especes';
  late Object? devise = widget.dossier['devise_id'];
  bool dansCaisse = true, busy = false;

  String _code(Object? id) => '${widget.devises.where((x) => '${x['id']}' == '$id').firstOrNull?['code'] ?? 'USD'}';
  bool get proposeCaisse => mode == 'especes' && widget.maCaisse != null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final d = widget.dossier, montant = parseAmount(_montant.text)!;
    final res = await widget.data.insert('paiements', {
      'source_type': 'dossier',
      'source_id': d['id'],
      'mode': mode,
      'montant': montant,
      'devise_id': devise,
      'reference': _ref.text.trim().isEmpty ? null : _ref.text.trim(),
      'recu_par': widget.profile.userId,
    });
    if (!mounted) return;
    if (!res.ok) {
      setState(() => busy = false);
      return toast(context, 'Erreur : ${res.error}');
    }
    var message = 'Encaissement de ${Elk.money(montant, _code(devise))} enregistré${savedSuffix(res.offline)}';
    // même argent, même geste : on l'ajoute à la caisse du jour si l'agent le souhaite
    if (proposeCaisse && dansCaisse) {
      final m = await widget.data.insert('mouvements_caisse', {
        'session_id': widget.maCaisse!['id'],
        'sens': 'entree',
        'libelle': 'Voyage ${d['ref']} · ${(d['clients'] as Map?)?['nom'] ?? ''}',
        'module': 'Voyage',
        'source_type': 'paiement',
        'source_id': res.data!['id'],
        'montant': montant,
        'devise_id': devise,
        'agent_id': widget.profile.userId,
      });
      message += m.ok ? ' · ajouté à votre caisse' : ' · (caisse non mise à jour : ${m.error})';
    }
    if (mounted) Navigator.pop(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dossier, e = widget.etat, muted = Theme.of(context).hintColor;
    String dev(num n) => Elk.money((n * 100).round() / 100, _code(d['devise_id']));
    return AlertDialog(
      title: Text('Encaisser · ${(d['clients'] as Map?)?['nom'] ?? ''}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Elk.navy.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _Montant('Total', dev(_num(d['montant'])))),
                      Expanded(child: _Montant('Déjà payé', dev(e.paye))),
                      Expanded(child: _Montant('Reste', dev(e.reste), couleur: e.reste > 0 ? Elk.crit : Elk.ok)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Comment le client paie-t-il ?', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    for (final m in _modes.entries)
                      ButtonSegment(
                        value: m.key,
                        label: Text(m.value),
                        icon: Icon(switch (m.key) {
                          'especes' => Icons.payments,
                          'mobile_money' => Icons.phone_android,
                          _ => Icons.account_balance,
                        }),
                      ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => setState(() => mode = s.first),
                ),
                const SizedBox(height: 14),
                formGrid([
                  AmountField(controller: _montant, label: 'Montant reçu'),
                  dropdown<Object?>('Devise', devise, {
                    for (final x in widget.devises) x['id']: '${x['code']}',
                  }, (v) => setState(() => devise = v)),
                  if (mode != 'especes')
                    TextFormField(
                      controller: _ref,
                      decoration: const InputDecoration(labelText: 'N° de transaction (facultatif)'),
                    ),
                ]),
                if (proposeCaisse)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: dansCaisse,
                    onChanged: (v) => setState(() => dansCaisse = v ?? true),
                    title: const Text('Ajouter aussi à ma caisse du jour'),
                    subtitle: const Text('Évite de saisir deux fois le même argent.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                if (widget.paiements.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Déjà reçu', style: TextStyle(fontWeight: FontWeight.w800)),
                  for (final p in widget.paiements)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${p['cree_le'] != null ? DateFormat('d MMM', 'fr_FR').format(DateTime.parse('${p['cree_le']}').toLocal()) : ''} · '
                        '${Elk.money(p['montant'], _code(p['devise_id']))} · ${_modes[p['mode']] ?? p['mode']}'
                        '${p['reference'] != null ? ' · ${p['reference']}' : ''}',
                        style: TextStyle(color: muted),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Fermer')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer le paiement')),
      ],
    );
  }
}

class _Montant extends StatelessWidget {
  const _Montant(this.label, this.valeur, {this.couleur});
  final String label, valeur;
  final Color? couleur;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      Text(
        valeur,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: couleur),
      ),
    ],
  );
}

// ------------------------------------------------------------------ nouveau / modifier un dossier
class _DossierDialog extends StatefulWidget {
  const _DossierDialog({
    required this.data,
    required this.profile,
    required this.clients,
    required this.devises,
    this.dossier,
    this.maCaisse,
  });
  final DataService data;
  final Profile profile;
  final List<JsonRow> clients, devises;
  final JsonRow? dossier; // null = création
  final JsonRow? maCaisse;
  @override
  State<_DossierDialog> createState() => _DossierDialogState();
}

class _DossierDialogState extends State<_DossierDialog> {
  final _form = GlobalKey<FormState>();
  late final JsonRow? d = widget.dossier;
  late List<JsonRow> clients = [...widget.clients];
  late String type = '${d?['type'] ?? 'billet'}';
  late Object? clientId = d?['client_id'];
  late final _dest = TextEditingController(text: '${d?['destination'] ?? ''}');
  late final _pays = TextEditingController(text: '${d?['pays'] ?? ''}');
  late final _hotel = TextEditingController(text: '${d?['hotel'] ?? ''}');
  late final _compagnie = TextEditingController(text: '${d?['compagnie'] ?? ''}');
  late final _reference = TextEditingController(text: '${d?['reference'] ?? ''}');
  late final _passager = TextEditingController(text: '${d?['passager'] ?? ''}');
  late final _montant = TextEditingController(text: d == null ? '' : '${d!['montant'] ?? ''}');
  late final _acompte = TextEditingController();
  late String? depart = d?['date_depart'] as String?, retour = d?['date_retour'] as String?;
  late bool allerSimple = d != null && d!['type'] == 'billet' && d!['date_retour'] == null && d!['date_depart'] != null;
  late String statut = d == null ? 'confirme' : (avancement(d!) == 'devis' ? 'devis' : 'confirme');
  late String? etape = d?['etape_visa'] as String? ?? 'a_deposer';
  late Object? devise =
      d?['devise_id'] ??
      (widget.devises.where((x) => x['code'] == 'USD').firstOrNull ?? widget.devises.firstOrNull)?['id'];
  bool acompte = false, busy = false;
  String modeAcompte = 'especes';

  Future<void> _choisirDate(bool estDepart) async {
    final now = DateTime.now();
    final init = DateTime.tryParse('${estDepart ? depart : retour ?? depart}') ?? now;
    final r = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 730)),
      locale: const Locale('fr', 'FR'),
    );
    if (r == null) return;
    setState(() {
      if (estDepart) {
        depart = jourCle(r);
        if (retour != null && retour!.compareTo(depart!) < 0) retour = null;
      } else {
        retour = jourCle(r);
      }
    });
  }

  Future<void> _nouveauClient() async {
    final nom = TextEditingController(), tel = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nouveau client'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nom,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom du client'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tel,
                decoration: const InputDecoration(labelText: 'Téléphone', hintText: '+243…'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, nom.text.trim().isNotEmpty), child: const Text('Ajouter')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.data.insert('clients', {
      'nom': nom.text.trim(),
      'telephone': tel.text.trim().isEmpty ? null : tel.text.trim(),
      'type': 'particulier',
      'cree_par': widget.profile.userId,
    });
    if (!mounted) return;
    if (!res.ok) return toast(context, 'Erreur : ${res.error}');
    setState(() {
      clients = [...clients, res.data!]..sort((a, b) => '${a['nom']}'.compareTo('${b['nom']}'));
      clientId = res.data!['id'];
    });
  }

  String? get _probleme {
    if (clientId == null) return 'Choisissez le client.';
    if (type == 'visa' && _pays.text.trim().isEmpty) return 'Indiquez le pays du visa.';
    if (type != 'visa' && _dest.text.trim().isEmpty && _hotel.text.trim().isEmpty) {
      return type == 'hotel' ? 'Indiquez l’hôtel ou la ville.' : 'Indiquez la destination.';
    }
    return null;
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _probleme != null) return;
    setState(() => busy = true);
    final row = <String, dynamic>{
      'client_id': clientId,
      'type': type,
      'destination': _opt(_dest),
      'pays': type == 'visa' ? _opt(_pays) : null,
      'hotel': type == 'hotel' ? _opt(_hotel) : null,
      'compagnie': {'billet', 'assurance', 'package'}.contains(type) ? _opt(_compagnie) : null,
      'reference': _opt(_reference),
      'passager': _opt(_passager),
      'date_depart': depart,
      'date_retour': type == 'visa' || (type == 'billet' && allerSimple) ? null : retour,
      'etape_visa': type == 'visa' ? etape : null,
      'montant': parseAmount(_montant.text) ?? 0,
      'devise_id': devise,
      // on ne touche pas à « effectué » / « annulé » depuis ce formulaire
      if (d == null || {'devis', 'confirme'}.contains(avancement(d!))) 'statut': statut,
    };
    final res = d == null
        ? await widget.data.insert('dossiers', {
            'ref': 'ELK-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
            'agent_id': widget.profile.userId,
            ...row,
          })
        : await widget.data.update('dossiers', d!['id'] as Object, row);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => busy = false);
      return toast(context, 'Erreur : ${res.error}');
    }
    // acompte reçu à la création : enregistré comme un encaissement
    final a = parseAmount(_acompte.text);
    if (d == null && acompte && a != null && a > 0) {
      final p = await widget.data.insert('paiements', {
        'source_type': 'dossier',
        'source_id': res.data!['id'],
        'mode': modeAcompte,
        'montant': a,
        'devise_id': devise,
        'recu_par': widget.profile.userId,
      });
      if (p.ok && modeAcompte == 'especes' && widget.maCaisse != null) {
        await widget.data.insert('mouvements_caisse', {
          'session_id': widget.maCaisse!['id'],
          'sens': 'entree',
          'libelle': 'Voyage ${res.data!['ref']} · acompte',
          'module': 'Voyage',
          'source_type': 'paiement',
          'source_id': p.data!['id'],
          'montant': a,
          'devise_id': devise,
          'agent_id': widget.profile.userId,
        });
      }
    }
    if (mounted) Navigator.pop(context, res);
  }

  Widget _boutonDate(String label, String? valeur, VoidCallback onTap) => OutlinedButton.icon(
    onPressed: onTap,
    icon: const Icon(Icons.calendar_month, size: 18),
    label: Text(valeur == null ? label : '$label : ${_date(valeur)}'),
  );

  @override
  Widget build(BuildContext context) {
    final probleme = _probleme;
    return AlertDialog(
      title: Text(d == null ? 'Nouveau dossier' : 'Modifier le dossier ${d!['ref']}'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Etape('1', 'Quel service ?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in typesDossier.entries)
                      ChoiceChip(
                        avatar: Icon(_icones[t.key], size: 18),
                        showCheckmark: false,
                        label: Text(t.value),
                        selected: type == t.key,
                        onSelected: (_) => setState(() => type = t.key),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Etape('2', 'Client'),
                Row(
                  children: [
                    Expanded(
                      child: dropdown<Object?>('Client', clientId, {
                        null: '— Choisir le client —',
                        for (final c in clients)
                          c['id']: '${c['nom']}${c['telephone'] != null ? ' · ${c['telephone']}' : ''}',
                      }, (v) => setState(() => clientId = v)),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _nouveauClient,
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Nouveau'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passager,
                  decoration: const InputDecoration(labelText: 'Voyageur, si ce n’est pas le client (facultatif)'),
                ),
                const SizedBox(height: 16),
                const Etape('3', 'Détails'),
                ...switch (type) {
                  'visa' => [
                    formGrid([
                      TextField(
                        controller: _pays,
                        decoration: const InputDecoration(labelText: 'Pays du visa', hintText: 'Afrique du Sud…'),
                      ),
                      dropdown<String?>('Où en est le visa ?', etape, {
                        for (final e in etapesVisa.entries) e.key: e.value,
                      }, (v) => setState(() => etape = v)),
                      TextField(
                        controller: _reference,
                        decoration: const InputDecoration(labelText: 'N° de dossier (facultatif)'),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _boutonDate('Date de voyage prévue', depart, () => _choisirDate(true)),
                  ],
                  'hotel' => [
                    formGrid([
                      TextField(
                        controller: _hotel,
                        decoration: const InputDecoration(labelText: 'Hôtel'),
                      ),
                      TextField(
                        controller: _dest,
                        decoration: const InputDecoration(labelText: 'Ville'),
                      ),
                      TextField(
                        controller: _reference,
                        decoration: const InputDecoration(labelText: 'N° de réservation (facultatif)'),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _boutonDate('Arrivée', depart, () => _choisirDate(true)),
                        _boutonDate('Départ', retour, () => _choisirDate(false)),
                      ],
                    ),
                  ],
                  _ => [
                    formGrid([
                      TextField(
                        controller: _dest,
                        decoration: InputDecoration(
                          labelText: type == 'billet' ? 'Trajet' : 'Destination',
                          hintText: 'Lubumbashi → Johannesburg',
                        ),
                      ),
                      TextField(
                        controller: _compagnie,
                        decoration: InputDecoration(
                          labelText: type == 'assurance' ? 'Assureur (facultatif)' : 'Compagnie (facultatif)',
                        ),
                      ),
                      TextField(
                        controller: _reference,
                        decoration: const InputDecoration(labelText: 'Référence / PNR (facultatif)'),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _boutonDate('Départ', depart, () => _choisirDate(true)),
                        if (!(type == 'billet' && allerSimple))
                          _boutonDate('Retour', retour, () => _choisirDate(false)),
                        if (type == 'billet')
                          FilterChip(
                            label: const Text('Aller simple'),
                            selected: allerSimple,
                            onSelected: (v) => setState(() => allerSimple = v),
                          ),
                      ],
                    ),
                  ],
                },
                const SizedBox(height: 16),
                const Etape('4', 'Prix et statut'),
                formGrid([
                  AmountField(controller: _montant, label: 'Prix total', allowZero: true),
                  dropdown<Object?>('Devise', devise, {
                    for (final x in widget.devises) x['id']: '${x['code']}',
                  }, (v) => setState(() => devise = v)),
                ]),
                if (d == null || {'devis', 'confirme'}.contains(avancement(d!))) ...[
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'devis',
                        label: Text('Simple devis'),
                        icon: Icon(Icons.request_quote_outlined),
                      ),
                      ButtonSegment(value: 'confirme', label: Text('Confirmé par le client'), icon: Icon(Icons.check)),
                    ],
                    selected: {statut},
                    onSelectionChanged: (s) => setState(() => statut = s.first),
                  ),
                ],
                if (d == null) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: acompte,
                    onChanged: (v) => setState(() => acompte = v),
                    title: const Text(
                      'Le client paie un acompte maintenant',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (acompte)
                    formGrid([
                      AmountField(controller: _acompte, label: 'Montant de l’acompte'),
                      dropdown<String>(
                        'Payé en',
                        modeAcompte,
                        _modes,
                        (v) => setState(() => modeAcompte = v ?? modeAcompte),
                      ),
                    ]),
                ],
                if (probleme != null && (clientId != null || _dest.text.isNotEmpty || _pays.text.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      probleme,
                      style: const TextStyle(color: Elk.crit, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: busy || probleme != null ? null : _save,
          child: Text(busy ? 'Enregistrement…' : 'Enregistrer'),
        ),
      ],
    );
  }
}
