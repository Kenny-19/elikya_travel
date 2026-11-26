// Bandeau « Nouvelle version disponible » + fenêtre de mise à jour (téléchargement, installation).
// La mise à jour n'est jamais imposée au milieu d'une saisie : l'agent clique quand il veut.
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/data_service.dart';
import '../data/mise_a_jour.dart';
import '../version.dart';
import 'theme.dart';

class BandeauMiseAJour extends StatelessWidget {
  const BandeauMiseAJour({super.key, required this.maj, required this.data});
  final MiseAJour maj;
  final DataService data;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Manifeste?>(
    valueListenable: maj.disponible,
    builder: (context, m, _) {
      if (m == null) return const SizedBox.shrink();
      return Material(
        color: Elk.accent.withValues(alpha: .16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt, color: Elk.accentText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Une nouvelle version de l’application est prête (${m.version}).',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => FenetreMiseAJour(maj: maj, manifeste: m, data: data),
                ),
                icon: const Icon(Icons.download),
                label: const Text('Mettre à jour maintenant'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class FenetreMiseAJour extends StatefulWidget {
  const FenetreMiseAJour({super.key, required this.maj, required this.manifeste, required this.data});
  final MiseAJour maj;
  final Manifeste manifeste;
  final DataService data;
  @override
  State<FenetreMiseAJour> createState() => _FenetreMiseAJourState();
}

class _FenetreMiseAJourState extends State<FenetreMiseAJour> {
  String etape = 'pret'; // pret | telechargement | installation | erreur
  double progres = 0;
  String? erreur;

  Future<void> _go() async {
    setState(() {
      etape = 'telechargement';
      progres = 0;
      erreur = null;
    });
    try {
      // d'abord envoyer ce qui attend sur le poste (rien n'est perdu de toute façon : les données restent)
      await widget.data.sync().timeout(const Duration(seconds: 20), onTimeout: () {});
      final f = await widget.maj.telecharger(
        widget.manifeste,
        Directory.systemTemp,
        (p) => mounted ? setState(() => progres = p) : null,
      );
      if (!mounted) return;
      setState(() => etape = 'installation');
      await Future<void>.delayed(const Duration(milliseconds: 1200)); // le temps de lire le message
      await widget.maj.installer(f);
    } catch (e) {
      if (mounted) {
        setState(() {
          etape = 'erreur';
          erreur = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    return AlertDialog(
      title: Text('Mettre à jour l’application (${widget.manifeste.version})'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version actuelle : $versionApp  →  nouvelle : ${widget.manifeste.version}',
              style: TextStyle(color: muted),
            ),
            if (widget.manifeste.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Ce qui change :', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(widget.manifeste.notes.trim()),
            ],
            const SizedBox(height: 16),
            if (etape == 'pret')
              Text(
                'Pendant la mise à jour, l’application se ferme puis se rouvre toute seule (environ une minute). '
                'Vos saisies sont gardées.',
                style: TextStyle(color: muted),
              ),
            if (etape == 'telechargement') ...[
              Text('Téléchargement… ${(progres * 100).round()} %', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progres == 0 ? null : progres),
            ],
            if (etape == 'installation')
              const Text(
                'Installation… l’application va se fermer et se rouvrir toute seule.',
                style: TextStyle(fontWeight: FontWeight.w700, color: Elk.ok),
              ),
            if (etape == 'erreur')
              Text(
                'La mise à jour n’a pas pu se faire : $erreur.\nVérifiez la connexion internet puis réessayez.',
                style: const TextStyle(color: Elk.crit),
              ),
          ],
        ),
      ),
      actions: [
        if (etape == 'pret' || etape == 'erreur')
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Plus tard')),
        if (etape == 'pret' || etape == 'erreur')
          FilledButton(onPressed: _go, child: Text(etape == 'erreur' ? 'Réessayer' : 'Mettre à jour maintenant')),
      ],
    );
  }
}
