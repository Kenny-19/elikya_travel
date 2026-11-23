// Coque de l'app : barre latérale (modules autorisés par le rôle) + bandeau réseau + page.
import 'package:flutter/material.dart';

import '../data/data_service.dart';
import '../profile.dart';
import 'modules.dart';
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
  late final List<ModuleDef> allowed = modules.where((m) => widget.profile.can(m.perm)).toList();
  int index = 0;
  int reload = 0; // incrémenté à la resynchronisation → la page relit la base en ligne

  @override
  void initState() {
    super.initState();
    widget.data.status.addListener(_onStatus);
  }

  @override
  void dispose() {
    widget.data.status.removeListener(_onStatus);
    super.dispose();
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
    width: 230,
    color: Elk.side,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 20, 18, 14),
          child: Text(
            'Elikya  ·  Agents',
            style: TextStyle(color: Elk.gold2, fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 10, 12, 6),
          child: Text('ACTIVITÉS', style: TextStyle(color: Elk.sideMuted, fontSize: 10, letterSpacing: 2)),
        ),
        for (var i = 0; i < modules.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            child: Material(
              color: i == index ? Elk.gold2.withValues(alpha: .14) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                leading: Icon(modules[i].icon, size: 19, color: i == index ? Elk.gold2 : Elk.sideInk),
                title: Text(
                  modules[i].label,
                  style: TextStyle(color: i == index ? Colors.white : Elk.sideInk, fontSize: 13.5),
                ),
                onTap: () => onSelect(i),
              ),
            ),
          ),
        const Spacer(),
        const Divider(color: Color(0xFF2C2D30), height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Elk.gold,
                child: Text(
                  profile.nom.isEmpty ? '?' : profile.nom.substring(0, 2).toUpperCase(),
                  style: const TextStyle(color: Color(0xFF19150C), fontSize: 12, fontWeight: FontWeight.w700),
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
