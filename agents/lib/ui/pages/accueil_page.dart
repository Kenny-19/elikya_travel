// Accueil — le point de départ, pensé pour quelqu'un qui n'est pas à l'aise avec l'ordinateur :
// « Bonjour Grace », de GROS boutons pour les gestes du quotidien, et « À faire aujourd'hui »
// (chaque ligne est cliquable et mène au bon endroit). N'affiche que ce que le rôle permet.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/data_service.dart';
import '../../data/location_logic.dart';
import '../../data/remote.dart';
import '../../data/voyage_logic.dart';
import '../../profile.dart';
import '../navigation.dart';
import '../theme.dart';

/// Un élément de la liste « À faire aujourd'hui ».
class AFaire {
  const AFaire(this.icone, this.couleur, this.texte, this.module, {this.action});
  final IconData icone;
  final Color couleur;
  final String texte;
  final String module;
  final String? action;
}

class AccueilPage extends StatefulWidget {
  const AccueilPage({super.key, required this.data, required this.profile});
  final DataService data;
  final Profile profile;
  @override
  State<AccueilPage> createState() => _AccueilPageState();
}

class _AccueilPageState extends State<AccueilPage> {
  bool loading = true;
  List<AFaire> aFaire = [];

  Profile get p => widget.profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = widget.data, now = DateTime.now(), today = jourCle(now), items = <AFaire>[];
    final dans3 = jourCle(now.add(const Duration(days: 3)));

    if (p.can('caisse') && p.userId != null) {
      final s = await d.select('caisse_sessions', Query(eq: {'statut': 'ouverte', 'agent_id': p.userId}));
      final ouvertes = s.data ?? [];
      if (!ouvertes.any((x) => x['jour'] == today)) {
        items.add(
          const AFaire(
            Icons.point_of_sale,
            Elk.navy2,
            'Votre caisse n’est pas encore ouverte aujourd’hui.',
            'caisse',
            action: 'ouvrir',
          ),
        );
      }
      for (final x in ouvertes.where((x) => '${x['jour']}'.compareTo(today) < 0)) {
        items.add(
          AFaire(
            Icons.lock_clock,
            Elk.warn,
            'La caisse du ${DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.parse('${x['jour']}'))} n’a pas été fermée.',
            'caisse',
          ),
        );
      }
    }
    if (p.can('location')) {
      final l = await d.select('locations', const Query(embed: ['clients(nom,telephone)']));
      for (final x in (l.data ?? []).where((x) => statutsActifs.contains(x['statut']))) {
        final nom = (x['clients'] as Map?)?['nom'] ?? 'Un client';
        if (enRetard(x, today)) {
          items.add(
            AFaire(
              Icons.warning_amber_rounded,
              Elk.crit,
              '$nom devait rendre le véhicule le ${jourCourt('${x['date_fin']}')}. Appelez-le : ${(x['clients'] as Map?)?['telephone'] ?? ''}',
              'location',
            ),
          );
        } else if (x['statut'] == 'reservee' && '${x['date_debut']}'.compareTo(today) <= 0) {
          items.add(
            AFaire(
              Icons.vpn_key,
              Elk.navy2,
              '$nom vient chercher son véhicule aujourd’hui : clés à remettre.',
              'location',
            ),
          );
        } else if (x['statut'] == 'en_cours' && x['date_fin'] == today) {
          items.add(AFaire(Icons.event, Elk.info, '$nom rend son véhicule aujourd’hui.', 'location'));
        }
      }
    }
    if (p.can('voyage')) {
      final r = await Future.wait([
        d.select(
          'dossiers',
          Query(embed: const ['clients(nom,telephone)'], gte: {'date_depart': today}, lte: {'date_depart': dans3}),
        ),
        d.select('paiements', const Query(eq: {'source_type': 'dossier'}, limit: 3000)),
        d.select('devises', const Query()),
      ]);
      final devises = r[2].data ?? [];
      String argent(num n, Object? deviseId) => Elk.money(
        (n * 100).round() / 100,
        '${devises.where((x) => '${x['id']}' == '$deviseId').firstOrNull?['code'] ?? 'USD'}',
      );
      for (final x in r[0].data ?? []) {
        final pay = etatPaiement(x, paiementsDe(r[1].data ?? [], x['id']), devises);
        if (departProcheNonSolde(x, pay, now)) {
          items.add(
            AFaire(
              Icons.flight_takeoff,
              Elk.crit,
              '${(x['clients'] as Map?)?['nom'] ?? 'Un client'} part le ${jourCourt('${x['date_depart']}')} et doit encore ${argent(pay.reste, x['devise_id'])}.',
              'voyage',
              action: 'non_soldes',
            ),
          );
        }
      }
    }
    if (p.can('momo')) {
      final m = await d.select('momo_transactions', const Query(eq: {'statut': 'en_attente'}));
      final n = (m.data ?? []).length;
      if (n > 0) {
        items.add(
          AFaire(
            Icons.hourglass_top,
            Elk.warn,
            n == 1
                ? '1 opération mobile money attend une confirmation.'
                : '$n opérations mobile money attendent une confirmation.',
            'momo',
          ),
        );
      }
    }
    if (p.can('fourniture')) {
      final c = await d.select('commandes', const Query(eq: {'statut': 'a_livrer'}));
      final n = (c.data ?? []).length;
      if (n > 0) {
        items.add(
          AFaire(
            Icons.local_shipping_outlined,
            Elk.info,
            n == 1 ? '1 commande à livrer.' : '$n commandes à livrer.',
            'fourniture',
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      aFaire = items;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prenom = p.nom.trim().split(RegExp(r'\s+')).first;
    final date = DateFormat('EEEE d MMMM y', 'fr_FR').format(DateTime.now());
    final actions = <(IconData, String, String, String?)>[
      if (p.can('voyage')) (Icons.flight_takeoff, 'Nouveau billet, visa ou hôtel', 'voyage', 'nouveau'),
      if (p.can('voyage')) (Icons.payments_outlined, 'Un client paie son voyage', 'voyage', 'non_soldes'),
      if (p.can('location')) (Icons.directions_car_outlined, 'Louer un véhicule', 'location', 'louer'),
      if (p.can('momo')) (Icons.south_west, 'Dépôt mobile money', 'momo', 'depot'),
      if (p.can('momo')) (Icons.north_east, 'Retrait mobile money', 'momo', 'retrait'),
      if (p.can('caisse')) (Icons.point_of_sale, 'Ma caisse du jour', 'caisse', null),
      if (p.can('fourniture')) (Icons.inventory_2_outlined, 'Nouvelle commande', 'fourniture', 'nouvelle_commande'),
      if (p.can('clients')) (Icons.person_add_alt, 'Nouveau client', 'clients', 'nouveau'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      children: [
        Text(
          'Bonjour $prenom 👋',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -.5),
        ),
        const SizedBox(height: 4),
        Text(
          '${date[0].toUpperCase()}${date.substring(1)} · Que voulez-vous faire ?',
          style: TextStyle(fontSize: 16, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final a in actions) _GrosBouton(icone: a.$1, texte: a.$2, onTap: () => Navigation.aller(a.$3, a.$4)),
          ],
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            const Text('À faire aujourd’hui', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Actualiser')),
          ],
        ),
        const SizedBox(height: 8),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (aFaire.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Elk.ok, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Rien d’urgent aujourd’hui. Bon travail !',
                    style: TextStyle(fontSize: 16, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
          )
        else
          for (final a in aFaire)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                leading: Icon(a.icone, color: a.couleur, size: 28),
                title: Text(a.texte, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigation.aller(a.module, a.action),
              ),
            ),
      ],
    );
  }
}

/// Grand bouton carré de l'accueil : une icône + une phrase simple.
class _GrosBouton extends StatelessWidget {
  const _GrosBouton({required this.icone, required this.texte, required this.onTap});
  final IconData icone;
  final String texte;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // même taille pour tous, mais grandit si le texte est plus grand (zoom Windows)
    constraints: const BoxConstraints(minWidth: 230, maxWidth: 230, minHeight: 150),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Elk.accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, color: Elk.accentText, size: 26),
              ),
              const SizedBox(height: 12),
              Text(texte, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.2)),
            ],
          ),
        ),
      ),
    ),
  );
}
