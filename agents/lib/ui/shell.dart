// Coque de l'app : barre latérale (modules autorisés par le rôle) + bandeau réseau + page.
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/data_service.dart';
import '../data/mise_a_jour.dart';
import '../profile.dart';
import 'mise_a_jour_ui.dart';
import 'modules.dart';
import 'navigation.dart';
import 'theme.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.data, required this.profile, required this.onSignOut});
  final DataService data;
  final Profile profile;
  final VoidCallback onSignOut;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final List<ModuleDef> allowed = modules.where((m) => m.visiblePour(widget.profile)).toList();
  int index = 0;
  int reload = 0; // incrémenté à la resynchronisation → la page relit la base en ligne
  Timer? _horloge, _majTimer; // mise à jour automatique des écrans toutes les 30 s (navigation.dart : Rafraichir)

  @override
  void initState() {
    super.initState();
    widget.data.status.addListener(_onStatus);
    Navigation.demande.addListener(_onNavigation);
    _horloge = Timer.periodic(const Duration(seconds: 30), (_) => Rafraichir.tick.value++);
    // mise à jour à distance : vérifier au démarrage puis toutes les 3 heures
    final maj = MiseAJour.instance;
    if (maj != null) {
      maj.verifier();
      _majTimer = Timer.periodic(const Duration(hours: 3), (_) => maj.verifier());
    }
  }

  @override
  void dispose() {
    _horloge?.cancel();
    _majTimer?.cancel();
    widget.data.status.removeListener(_onStatus);
    Navigation.demande.removeListener(_onNavigation);
    super.dispose();
  }

  // l'accueil (ou une autre page) demande d'aller dans un module
  void _onNavigation() {
    final d = Navigation.demande.value;
    if (d == null) return;
    final i = allowed.indexWhere((m) => m.id == d.$1);
    if (i >= 0 && i != index && mounted) setState(() => index = i);
  }

  void _onStatus() {
    final s = widget.data.status.value;
    if (s.synced && s.online && mounted) {
      setState(() => reload++);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Connexion rétablie · données synchronisées ✓')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = allowed[index];
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            modules: allowed,
            index: index,
            profile: widget.profile,
            onSelect: (i) => setState(() => index = i),
            onSignOut: widget.onSignOut,
          ),
          Expanded(
            child: Column(
              children: [
                NetBanner(data: widget.data),
                if (MiseAJour.instance != null) BandeauMiseAJour(maj: MiseAJour.instance!, data: widget.data),
                Expanded(
                  child: KeyedSubtree(key: ValueKey('${m.id}-$reload'), child: m.build(widget.data, widget.profile)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.modules,
    required this.index,
    required this.profile,
    required this.onSelect,
    required this.onSignOut,
  });
  final List<ModuleDef> modules;
  final int index;
  final Profile profile;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Container(
    width: 240,
    color: Elk.side,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 20, 14, 16),
          child: ElikyaLogo(size: 36, onDark: true, subtitle: 'Agents'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 10, 12, 6),
          child: Text(
            'ACTIVITÉS',
            style: TextStyle(color: Elk.sideMuted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700),
          ),
        ),
        for (var i = 0; i < modules.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            child: Material(
              color: i == index ? Elk.side2 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: Container(
                // repère orange de la page active (comme le site)
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: i == index ? Elk.accent : Colors.transparent, width: 3)),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(modules[i].icon, size: 19, color: i == index ? Elk.accent : Elk.sideMuted),
                  title: Text(
                    modules[i].label,
                    style: TextStyle(
                      color: i == index ? Colors.white : Elk.sideInk,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => onSelect(i),
                ),
              ),
            ),
          ),
        const Spacer(),
        const Divider(color: Color(0xFF1D3A66), height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Elk.accent,
                child: Text(
                  profile.nom.isEmpty ? '?' : profile.nom.substring(0, 2).toUpperCase(),
                  style: const TextStyle(color: Elk.navy, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.nom,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Elk.sideInk, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      profile.role,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Elk.sideMuted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onSignOut,
                child: const Text('Quitter', style: TextStyle(color: Elk.sideMuted, fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Bandeau : hors ligne / synchro en cours / saisies refusées.
class NetBanner extends StatelessWidget {
  const NetBanner({super.key, required this.data});
  final DataService data;

  Future<void> _showFailed(BuildContext context) async {
    final items = await data.local.failed();
    if (!context.mounted) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Saisies refusées par la base en ligne'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final it in items)
                ListTile(
                  dense: true,
                  title: Text('${it.tbl} · ${it.op} · ${it.at.toLocal().toString().substring(0, 16)}'),
                  subtitle: Text(it.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fermer')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Effacer la liste')),
        ],
      ),
    );
    if (clear == true) {
      await data.local.clearFailed();
      await data.refreshCounts();
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<NetStatus>(
    valueListenable: data.status,
    builder: (context, s, _) {
      final parts = <String>[
        if (!s.online)
          'Hors ligne — base en ligne injoignable. Les saisies sont gardées sur ce poste'
              '${s.pending > 0 ? ' (${s.pending} en attente)' : ''} et seront envoyées au retour du réseau.'
        else if (s.pending > 0)
          'Synchronisation en cours… ${s.pending} saisie(s) à envoyer.',
        if (s.failed > 0) '${s.failed} saisie(s) refusée(s) par la base en ligne.',
      ];
      if (parts.isEmpty) return const SizedBox.shrink();
      final color = s.online ? Elk.info : Elk.warn;
      return Container(
        width: double.infinity,
        color: color.withValues(alpha: .12),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            Icon(s.online ? Icons.sync : Icons.cloud_off, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(parts.join('  ·  '), style: TextStyle(color: color, fontSize: 12.5)),
            ),
            if (s.failed > 0) TextButton(onPressed: () => _showFailed(context), child: const Text('Voir')),
            if (!s.online) TextButton(onPressed: data.probe, child: const Text('Réessayer')),
          ],
        ),
      );
    },
  );
}
