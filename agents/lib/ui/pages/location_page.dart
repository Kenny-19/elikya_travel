// Module Location de véhicules — pensé pour être TRÈS simple à utiliser :
// - une carte par véhicule, avec son état en couleur et UN gros bouton d'action
//   (Louer · Remettre les clés · Véhicule rendu) ;
// - louer = choisir le client + les dates dans un calendrier + « avec chauffeur » ;
//   le montant se calcule tout seul ; le reste est replié dans « Plus d'options ».
// Règles (jours, conflits, état) : lib/data/location_logic.dart (testées).
// La base interdit aussi deux locations qui se chevauchent (db/location.sql).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/data_service.dart';
import '../../data/local_db.dart';
import '../../data/location_logic.dart';
import '../../data/remote.dart';
import '../../profile.dart';
import '../theme.dart';
import '../widgets.dart';

String _usd(num n) => Elk.money((n * 100).round() / 100, 'USD');
num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
String _dateLongue(String k) => DateFormat('EEE d MMM', 'fr_FR').format(DateTime.parse(k));

/// Couleur et icône de chaque état (toujours accompagnées d'un libellé, jamais la couleur seule).
(Color, IconData) styleEtat(String code) => switch (code) {
  'disponible' || 'reserve_plus_tard' => (Elk.ok, Icons.check_circle),
  'loue' => (Elk.info, Icons.vpn_key),
  'a_remettre' => (Elk.navy2, Icons.event_available),
  'retard' => (Elk.crit, Icons.warning_amber_rounded),
  'entretien' => (Elk.warn, Icons.build_circle),
  _ => (Elk.slate, Icons.block),
};

class LocationPage extends StatefulWidget {
  const LocationPage({super.key, required this.data, required this.profile});
  final DataService data;
  final Profile profile;
  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  bool loading = true;
  String? error;
  List<JsonRow> vehicules = [], locations = [], clients = [], devises = [];
  bool historique = false;

  DataService get data => widget.data;
  String get today => jourCle(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final r = await Future.wait([
      data.select('vehicules', const Query(orderBy: 'marque')),
      data.select(
        'locations',
        const Query(embed: ['clients(nom,telephone)'], orderBy: 'date_debut', ascending: false, limit: 600),
      ),
      data.select('clients', const Query(orderBy: 'nom')),
      data.select('devises', const Query(orderBy: 'id')),
    ]);
    if (!mounted) return;
    setState(() {
      vehicules = (r[0].data ?? []).where((v) => v['actif'] != false).toList();
      locations = r[1].data ?? [];
      clients = r[2].data ?? [];
      devises = r[3].data ?? [];
      error = r.map((x) => x.error).whereType<String>().firstOrNull;
      loading = false;
    });
  }

  JsonRow? _vehicule(Object? id) => vehicules.where((v) => '${v['id']}' == '$id').firstOrNull;

  // ---------------------------------------------------------------- actions
  Future<void> _louer([JsonRow? vehicule]) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _LouerDialog(
        data: data,
        profile: widget.profile,
        vehicules: vehicules,
        locations: locations,
        clients: clients,
        devises: devises,
        vehicule: vehicule,
      ),
    );
    if (res == null || !mounted) return;
    toast(context, 'Location ${res.data!['ref']} enregistrée${savedSuffix(res.offline)}');
    _load();
  }

  Future<void> _vehiculeForm([JsonRow? v]) async {
    final res = await showDialog<DataResult<JsonRow>>(
      context: context,
      builder: (_) => _VehiculeDialog(
        data: data,
        vehicule: v,
        immatriculations: {for (final x in vehicules) '${x['immatriculation']}'},
      ),
    );
    if (res == null || !mounted) return;
    toast(context, 'Véhicule enregistré${savedSuffix(res.offline)}');
    _load();
  }

  Future<void> _changerStatut(JsonRow l, String statut, String message) async {
    final res = await data.update('locations', l['id'] as Object, {'statut': statut});
    if (!mounted) return;
    toast(context, res.ok ? '$message${savedSuffix(res.offline)}' : 'Erreur : ${res.error}');
    _load();
  }

  Future<void> _annuler(JsonRow l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Annuler cette location ?'),
        content: Text(
          '${l['ref']} · ${(l['clients'] as Map?)?['nom'] ?? ''}\n'
          'Du ${_dateLongue('${l['date_debut']}')} au ${_dateLongue('${l['date_fin']}')}.\n\n'
          'Le véhicule redevient libre sur ces dates.',
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
    if (ok == true) _changerStatut(l, 'annulee', 'Location annulée');
  }

  Future<void> _entretien(JsonRow v, bool enEntretien) async {
    final res = await data.update('vehicules', v['id'] as Object, {'statut': enEntretien ? 'entretien' : 'disponible'});
    if (!mounted) return;
    toast(
      context,
      res.ok
          ? (enEntretien ? 'Véhicule mis en entretien' : 'Véhicule remis en service') + savedSuffix(res.offline)
          : 'Erreur : ${res.error}',
    );
    _load();
  }

  // ---------------------------------------------------------------- écran
  @override
  Widget build(BuildContext context) {
    final etats = {for (final v in vehicules) v['id']: etatVehicule(v, locations, today)};
    // ordre des cartes : d'abord ce qui demande une action, puis les véhicules libres
    const ordre = ['a_remettre', 'retard', 'disponible', 'reserve_plus_tard', 'loue', 'entretien', 'hors_service'];
    final tries = [...vehicules]
      ..sort((a, b) => ordre.indexOf(etats[a['id']]!.code).compareTo(ordre.indexOf(etats[b['id']]!.code)));
    int nb(String c) => etats.values.where((e) => e.code == c).length;
    final libres = nb('disponible') + nb('reserve_plus_tard');
    final retards = locations.where((l) => enRetard(l, today)).toList();
    final aRendre = locations.where((l) => l['statut'] == 'en_cours' && l['date_fin'] == today).length;
    final aVenir = locations.where((l) => statutsActifs.contains(l['statut'])).toList()
      ..sort((a, b) => '${a['date_debut']}'.compareTo('${b['date_debut']}'));
    final passees = locations.where((l) => !statutsActifs.contains(l['statut'])).take(30).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        PageHeader(
          title: 'Location de véhicules',
          subtitle: 'Choisissez un véhicule libre et cliquez sur « Louer ».',
          actions: [
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rafraîchir'),
            ),
            OutlinedButton.icon(
              onPressed: () => _vehiculeForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter un véhicule'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Compteur(Icons.check_circle, Elk.ok, '$libres', libres > 1 ? 'disponibles' : 'disponible'),
            if (nb('loue') + nb('retard') > 0)
              _Compteur(Icons.vpn_key, Elk.info, '${nb('loue') + nb('retard')}', 'en location'),
            if (nb('a_remettre') > 0)
              _Compteur(Icons.event_available, Elk.navy2, '${nb('a_remettre')}', 'clés à remettre'),
            if (aRendre > 0) _Compteur(Icons.event, Elk.navy2, '$aRendre', 'à rendre aujourd’hui'),
            if (retards.isNotEmpty) _Compteur(Icons.warning_amber_rounded, Elk.crit, '${retards.length}', 'en retard'),
          ],
        ),
        if (retards.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Bandeau(
            couleur: Elk.crit,
            icone: Icons.warning_amber_rounded,
            texte: retards.length == 1
                ? '1 véhicule aurait dû être rendu. Appelez le client.'
                : '${retards.length} véhicules auraient dû être rendus. Appelez les clients.',
            details: [
              for (final l in retards)
                '${_vehicule(l['vehicule_id'])?['marque'] ?? ''} ${_vehicule(l['vehicule_id'])?['immatriculation'] ?? ''} · '
                    '${(l['clients'] as Map?)?['nom'] ?? ''} ${(l['clients'] as Map?)?['telephone'] ?? ''} · prévu le ${_dateLongue('${l['date_fin']}')}',
            ],
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Erreur : $error', style: const TextStyle(color: Elk.crit)),
          ),
        const SizedBox(height: 22),
        const _Titre('Nos véhicules'),
        const SizedBox(height: 10),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (vehicules.isEmpty)
          _Vide(
            icone: Icons.directions_car_outlined,
            texte: 'Aucun véhicule pour l’instant.',
            bouton: FilledButton.icon(
              onPressed: () => _vehiculeForm(),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter le premier véhicule'),
            ),
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final v in tries)
                _CarteVehicule(
                  vehicule: v,
                  etat: etats[v['id']]!,
                  today: today,
                  onLouer: () => _louer(v),
                  onRemettre: (l) => _changerStatut(l, 'en_cours', 'Clés remises — location en cours'),
                  onRendu: (l) => _changerStatut(l, 'terminee', 'Véhicule rendu — location terminée'),
                  onModifier: () => _vehiculeForm(v),
                  onEntretien: (on) => _entretien(v, on),
                ),
            ],
          ),
        const SizedBox(height: 26),
        Row(
          children: [
            const _Titre('Locations en cours et à venir'),
            const Spacer(),
            if (vehicules.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _louer(),
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle location'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (!loading && aVenir.isEmpty)
          const _Vide(icone: Icons.event_available, texte: 'Aucune location en cours ni à venir.')
        else
          for (final l in aVenir)
            _LigneLocation(
              location: l,
              vehicule: _vehicule(l['vehicule_id']),
              today: today,
              onRemettre: () => _changerStatut(l, 'en_cours', 'Clés remises — location en cours'),
              onRendu: () => _changerStatut(l, 'terminee', 'Véhicule rendu — location terminée'),
              onAnnuler: () => _annuler(l),
            ),
        const SizedBox(height: 14),
        if (passees.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() => historique = !historique),
            icon: Icon(historique ? Icons.expand_less : Icons.expand_more),
            label: Text(historique ? 'Masquer l’historique' : 'Voir l’historique (${passees.length} dernières)'),
          ),
        if (historique)
          for (final l in passees) _LigneLocation(location: l, vehicule: _vehicule(l['vehicule_id']), today: today),
      ],
    );
  }
}

// ------------------------------------------------------------------ petits éléments
class _Titre extends StatelessWidget {
  const _Titre(this.texte);
  final String texte;
  @override
  Widget build(BuildContext context) => Text(texte, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
}

class _Compteur extends StatelessWidget {
  const _Compteur(this.icone, this.couleur, this.valeur, this.libelle);
  final IconData icone;
  final Color couleur;
  final String valeur, libelle;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, color: couleur, size: 26),
          const SizedBox(width: 12),
          Text(valeur, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text(
            libelle,
            style: TextStyle(color: Theme.of(context).hintColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({required this.couleur, required this.icone, required this.texte, this.details = const []});
  final Color couleur;
  final IconData icone;
  final String texte;
  final List<String> details;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: couleur.withValues(alpha: .35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, color: couleur),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                texte,
                style: TextStyle(color: couleur, fontWeight: FontWeight.w800),
              ),
              for (final d in details) Padding(padding: const EdgeInsets.only(top: 4), child: Text(d)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Vide extends StatelessWidget {
  const _Vide({required this.icone, required this.texte, this.bouton});
  final IconData icone;
  final String texte;
  final Widget? bouton;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          children: [
            Icon(icone, size: 40, color: Theme.of(context).hintColor),
            const SizedBox(height: 10),
            Text(texte, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 15)),
            if (bouton != null) ...[const SizedBox(height: 14), bouton!],
          ],
        ),
      ),
    ),
  );
}

/// Carte d'un véhicule : état en couleur + UN bouton principal adapté à la situation.
class _CarteVehicule extends StatelessWidget {
  const _CarteVehicule({
    required this.vehicule,
    required this.etat,
    required this.today,
    required this.onLouer,
    required this.onRemettre,
    required this.onRendu,
    required this.onModifier,
    required this.onEntretien,
  });
  final JsonRow vehicule;
  final EtatVehicule etat;
  final String today;
  final VoidCallback onLouer, onModifier;
  final ValueChanged<JsonRow> onRemettre, onRendu;
  final ValueChanged<bool> onEntretien;

  @override
  Widget build(BuildContext context) {
    final v = vehicule, l = etat.location;
    final (couleur, icone) = styleEtat(etat.code);
    final client = (l?['clients'] as Map?)?['nom'];

    // bouton principal selon la situation
    final Widget action = switch (etat.code) {
      'disponible' || 'reserve_plus_tard' => FilledButton.icon(
        onPressed: onLouer,
        icon: const Icon(Icons.key),
        label: const Text('Louer'),
      ),
      'a_remettre' => FilledButton.icon(
        onPressed: () => onRemettre(l!),
        icon: const Icon(Icons.vpn_key),
        label: const Text('Remettre les clés'),
      ),
      'loue' || 'retard' => FilledButton.icon(
        onPressed: () => onRendu(l!),
        icon: const Icon(Icons.assignment_turned_in),
        label: const Text('Véhicule rendu'),
      ),
      'entretien' => OutlinedButton.icon(
        onPressed: () => onEntretien(false),
        icon: const Icon(Icons.check),
        label: const Text('Remettre en service'),
      ),
      _ => const SizedBox.shrink(),
    };

    return SizedBox(
      width: 300,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: couleur.withValues(alpha: .12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(icone, color: couleur, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      etat.libelle,
                      style: TextStyle(color: couleur, fontWeight: FontWeight.w800),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Plus',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (c) => c == 'modifier' ? onModifier() : onEntretien(c == 'entretien'),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'modifier', child: Text('Modifier le véhicule')),
                      if (v['statut'] != 'entretien' && !{'loue', 'retard', 'a_remettre'}.contains(etat.code))
                        const PopupMenuItem(value: 'entretien', child: Text('Mettre en entretien')),
                      if (v['statut'] == 'entretien')
                        const PopupMenuItem(value: 'service', child: Text('Remettre en service')),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${v['marque']} ${v['modele'] ?? ''}'.trim(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${v['immatriculation']} · ${v['places']} places${v['carburant'] != null ? ' · ${v['carburant']}' : ''}',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                  const SizedBox(height: 10),
                  Text('${_usd(_num(v['tarif_jour']))} / jour', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (_num(v['tarif_chauffeur_jour']) > 0)
                    Text(
                      'Avec chauffeur : + ${_usd(_num(v['tarif_chauffeur_jour']))} / jour',
                      style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
                    ),
                  if (l != null && client != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '$client · ${_dateLongue('${l['date_debut']}')} → ${_dateLongue('${l['date_fin']}')}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: action),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une location dans la liste, avec ses actions en clair.
class _LigneLocation extends StatelessWidget {
  const _LigneLocation({
    required this.location,
    required this.vehicule,
    required this.today,
    this.onRemettre,
    this.onRendu,
    this.onAnnuler,
  });
  final JsonRow location;
  final JsonRow? vehicule;
  final String today;
  final VoidCallback? onRemettre, onRendu, onAnnuler;

  @override
  Widget build(BuildContext context) {
    final l = location, muted = Theme.of(context).hintColor;
    final (label, couleur) = switch (l['statut']) {
      'reservee' => ('Réservée', Elk.navy2),
      'en_cours' => enRetard(l, today) ? ('En retard', Elk.crit) : ('En cours', Elk.info),
      'terminee' => ('Terminée', Elk.ok),
      _ => ('Annulée', Elk.slate),
    };
    final jours = joursLocation('${l['date_debut']}', '${l['date_fin']}');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Pill(label, couleur),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(l['clients'] as Map?)?['nom'] ?? '—'} · ${vehicule?['marque'] ?? ''} ${vehicule?['immatriculation'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Du ${_dateLongue('${l['date_debut']}')} au ${_dateLongue('${l['date_fin']}')} · $jours jour${jours > 1 ? 's' : ''}'
                    '${l['avec_chauffeur'] == true ? ' · avec chauffeur${l['chauffeur'] != null ? ' (${l['chauffeur']})' : ''}' : ''}',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            Text(Elk.money(l['montant'], 'USD'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(width: 14),
            if (l['statut'] == 'reservee' && onRemettre != null)
              FilledButton(onPressed: onRemettre, child: const Text('Remettre les clés')),
            if (l['statut'] == 'en_cours' && onRendu != null)
              FilledButton(onPressed: onRendu, child: const Text('Véhicule rendu')),
            if (l['statut'] == 'reservee' && onAnnuler != null)
              IconButton(tooltip: 'Annuler la location', onPressed: onAnnuler, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ louer
class _LouerDialog extends StatefulWidget {
  const _LouerDialog({
    required this.data,
    required this.profile,
    required this.vehicules,
    required this.locations,
    required this.clients,
    required this.devises,
    this.vehicule,
  });
  final DataService data;
  final Profile profile;
  final List<JsonRow> vehicules, locations, clients, devises;
  final JsonRow? vehicule;
  @override
  State<_LouerDialog> createState() => _LouerDialogState();
}

class _LouerDialogState extends State<_LouerDialog> {
  late List<JsonRow> clients = [...widget.clients];
  late Object? vehiculeId = (widget.vehicule ?? widget.vehicules.first)['id'];
  Object? clientId;
  DateTimeRange? dates;
  bool chauffeur = false, partMaintenant = true, options = false, montantManuel = false, busy = false;
  final _chauffeur = TextEditingController();
  final _montant = TextEditingController();
  final _caution = TextEditingController(text: '0');
  final _notes = TextEditingController();
  late Object? devise =
      (widget.devises.where((d) => d['code'] == 'USD').firstOrNull ?? widget.devises.firstOrNull)?['id'];

  JsonRow get vehicule => widget.vehicules.firstWhere((v) => v['id'] == vehiculeId);
  String? get debut => dates == null ? null : jourCle(dates!.start);
  String? get fin => dates == null ? null : jourCle(dates!.end);
  JsonRow? get conflit => dates == null ? null : conflitLocation(widget.locations, vehiculeId, debut!, fin!);
  bool get commenceAujourdhui => debut == jourCle(DateTime.now());

  void _recalculer() {
    if (!montantManuel && dates != null) {
      _montant.text = montantConseille(vehicule, debut!, fin!, chauffeur).toString();
    }
  }

  Future<void> _choisirDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: dates,
      locale: const Locale('fr', 'FR'),
      helpText: 'Du … au … (jour de retour inclus)',
      saveText: 'Valider',
    );
    if (r != null) {
      setState(() {
        dates = r;
        _recalculer();
      });
    }
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
    if (dates == null) return 'Choisissez les dates.';
    final c = conflit;
    if (c != null) {
      return 'Ce véhicule est déjà pris du ${_dateLongue('${c['date_debut']}')} au ${_dateLongue('${c['date_fin']}')}'
          '${(c['clients'] as Map?)?['nom'] != null ? ' (${(c['clients'] as Map)['nom']})' : ''} — choisissez d’autres dates ou un autre véhicule.';
    }
    if (vehicule['statut'] != 'disponible') return 'Ce véhicule est en entretien ou hors service.';
    if ((parseAmount(_montant.text) ?? -1) < 0) return 'Montant invalide.';
    return null;
  }

  Future<void> _enregistrer() async {
    if (_probleme != null) return;
    setState(() => busy = true);
    final res = await widget.data.insert('locations', {
      'ref': 'LOC-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      'client_id': clientId,
      'vehicule_id': vehiculeId,
      'date_debut': debut,
      'date_fin': fin,
      'avec_chauffeur': chauffeur,
      'chauffeur': chauffeur && _chauffeur.text.trim().isNotEmpty ? _chauffeur.text.trim() : null,
      'montant': parseAmount(_montant.text) ?? 0,
      'devise_id': devise,
      'caution': parseAmount(_caution.text) ?? 0,
      'statut': commenceAujourdhui && partMaintenant ? 'en_cours' : 'reservee',
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'agent_id': widget.profile.userId,
    });
    if (!mounted) return;
    if (!res.ok) {
      setState(() => busy = false);
      return toast(
        context,
        res.error!.contains('chevauchement')
            ? 'Ce véhicule vient d’être réservé sur ces dates par un autre poste.'
            : 'Erreur : ${res.error}',
      );
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    final probleme = _probleme;
    final jours = dates == null ? 0 : joursLocation(debut!, fin!);
    return AlertDialog(
      title: const Text('Louer un véhicule'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Etape('1', 'Véhicule'),
              dropdown<Object?>(
                'Véhicule',
                vehiculeId,
                {
                  for (final v in widget.vehicules.where((v) => v['statut'] == 'disponible'))
                    v['id']:
                        '${v['marque']} ${v['modele'] ?? ''} · ${v['immatriculation']} · ${_usd(_num(v['tarif_jour']))}/jour',
                },
                (v) => setState(() {
                  vehiculeId = v;
                  _recalculer();
                }),
              ),
              const SizedBox(height: 16),
              _Etape('2', 'Client'),
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
              const SizedBox(height: 16),
              _Etape('3', 'Dates'),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _choisirDates,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    dates == null
                        ? 'Choisir les dates dans le calendrier'
                        : 'Du ${_dateLongue(debut!)} au ${_dateLongue(fin!)} · $jours jour${jours > 1 ? 's' : ''}',
                  ),
                ),
              ),
              if (commenceAujourdhui)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: partMaintenant,
                  onChanged: (v) => setState(() => partMaintenant = v ?? true),
                  title: const Text('Le client part maintenant avec le véhicule'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              const SizedBox(height: 8),
              _Etape('4', 'Chauffeur'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: chauffeur,
                onChanged: (v) => setState(() {
                  chauffeur = v;
                  _recalculer();
                }),
                title: Text(
                  chauffeur ? 'Avec chauffeur' : 'Sans chauffeur',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: _num(vehicule['tarif_chauffeur_jour']) > 0
                    ? Text('+ ${_usd(_num(vehicule['tarif_chauffeur_jour']))} par jour')
                    : null,
              ),
              if (chauffeur)
                TextField(
                  controller: _chauffeur,
                  decoration: const InputDecoration(labelText: 'Nom du chauffeur (facultatif)'),
                ),
              const SizedBox(height: 16),
              // total, bien visible
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Elk.navy.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _montant,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        decoration: const InputDecoration(suffixText: ' \$', hintText: '—'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() => montantManuel = true),
                      ),
                    ),
                  ],
                ),
              ),
              if (dates != null && !montantManuel)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Calculé : $jours jour${jours > 1 ? 's' : ''} × ${_usd(_num(vehicule['tarif_jour']) + (chauffeur ? _num(vehicule['tarif_chauffeur_jour']) : 0))}. Modifiable si remise.',
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () => setState(() => options = !options),
                icon: Icon(options ? Icons.expand_less : Icons.expand_more),
                label: const Text('Plus d’options (caution, devise, remarque)'),
              ),
              if (options)
                formGrid([
                  AmountField(controller: _caution, label: 'Caution reçue', allowZero: true, required: false),
                  dropdown<Object?>('Devise', devise, {
                    for (final d in widget.devises) d['id']: '${d['code']}',
                  }, (v) => devise = v),
                  TextField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Remarque'),
                  ),
                ]),
              if (probleme != null && (dates != null || clientId != null))
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
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: busy || probleme != null ? null : _enregistrer,
          child: Text(
            busy ? 'Enregistrement…' : (commenceAujourdhui && partMaintenant ? 'Louer maintenant' : 'Réserver'),
          ),
        ),
      ],
    );
  }
}

class _Etape extends StatelessWidget {
  const _Etape(this.numero, this.titre);
  final String numero, titre;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: Elk.navy,
          child: Text(
            numero,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Text(titre, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

// ------------------------------------------------------------------ véhicule
class _VehiculeDialog extends StatefulWidget {
  const _VehiculeDialog({required this.data, this.vehicule, required this.immatriculations});
  final DataService data;
  final JsonRow? vehicule;
  final Set<String> immatriculations;
  @override
  State<_VehiculeDialog> createState() => _VehiculeDialogState();
}

class _VehiculeDialogState extends State<_VehiculeDialog> {
  final _form = GlobalKey<FormState>();
  late final v = widget.vehicule;
  late final _immat = TextEditingController(text: '${v?['immatriculation'] ?? ''}');
  late final _marque = TextEditingController(text: '${v?['marque'] ?? ''}');
  late final _modele = TextEditingController(text: '${v?['modele'] ?? ''}');
  late final _places = TextEditingController(text: '${v?['places'] ?? 5}');
  late final _tarif = TextEditingController(text: '${v?['tarif_jour'] ?? ''}');
  late final _chauffeur = TextEditingController(text: '${v?['tarif_chauffeur_jour'] ?? 0}');
  late String carburant = ['Essence', 'Diesel'].contains(v?['carburant']) ? v!['carburant'] as String : 'Diesel';
  bool busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final row = {
      'marque': _marque.text.trim(),
      'modele': _modele.text.trim().isEmpty ? null : _modele.text.trim(),
      'places': int.parse(_places.text.trim()),
      'carburant': carburant,
      'tarif_jour': parseAmount(_tarif.text),
      'tarif_chauffeur_jour': parseAmount(_chauffeur.text) ?? 0,
    };
    final res = v == null
        ? await widget.data.insert('vehicules', {
            'immatriculation': _immat.text.trim().toUpperCase(),
            'statut': 'disponible',
            ...row,
          })
        : await widget.data.update('vehicules', v!['id'] as Object, row);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => busy = false);
      return toast(context, res.code == '23505' ? 'Cette immatriculation existe déjà.' : 'Erreur : ${res.error}');
    }
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(v == null ? 'Ajouter un véhicule' : 'Modifier ${v!['marque']} ${v!['immatriculation']}'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: formGrid([
          TextFormField(
            controller: _immat,
            enabled: v == null,
            decoration: const InputDecoration(labelText: 'Plaque d’immatriculation'),
            validator: (x) {
              if (v != null) return null;
              final p = (x ?? '').trim().toUpperCase();
              if (p.isEmpty) return 'Plaque requise';
              return widget.immatriculations.contains(p) ? 'Ce véhicule existe déjà' : null;
            },
          ),
          TextFormField(
            controller: _marque,
            decoration: const InputDecoration(labelText: 'Marque', hintText: 'Toyota…'),
            validator: (x) => (x ?? '').trim().isEmpty ? 'Marque requise' : null,
          ),
          TextFormField(
            controller: _modele,
            decoration: const InputDecoration(labelText: 'Modèle', hintText: 'Hilux, Prado…'),
          ),
          TextFormField(
            controller: _places,
            decoration: const InputDecoration(labelText: 'Places'),
            keyboardType: TextInputType.number,
            validator: (x) => (int.tryParse((x ?? '').trim()) ?? 0) > 0 ? null : 'Nombre de places',
          ),
          dropdown<String>('Carburant', carburant, const {
            'Diesel': 'Diesel',
            'Essence': 'Essence',
          }, (x) => carburant = x ?? carburant),
          AmountField(controller: _tarif, label: 'Prix par jour (USD)'),
          AmountField(
            controller: _chauffeur,
            label: 'Supplément chauffeur / jour (USD)',
            allowZero: true,
            required: false,
          ),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Enregistrement…' : 'Enregistrer')),
    ],
  );
}
