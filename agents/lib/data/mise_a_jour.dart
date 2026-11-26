// Mise à jour à distance de l'application des agents.
//
// À chaque nouvelle version, `node scripts/publier-agents.js` publie sur GitHub (Releases du dépôt) :
//   - l'installeur  Elikya-Agents-Setup-<version>.exe
//   - le manifeste  agents.json  {version, build, url, sha256, notes}
// L'application lit le manifeste de la DERNIÈRE version (au démarrage puis toutes les 3 heures).
// Si son numéro (build) est plus grand, un bandeau propose « Mettre à jour maintenant » :
// téléchargement → contrôle d'intégrité (empreinte SHA-256) → installation silencieuse (/S)
// → l'installeur ferme l'app, remplace les fichiers et la relance. Les données locales
// (saisies hors ligne en attente) sont ailleurs et ne sont jamais touchées.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../version.dart';

const depotReleases = 'https://github.com/Kenny-19/elikya_travel/releases/';
const manifesteParDefaut = '${depotReleases}latest/download/agents.json';

class Manifeste {
  const Manifeste({
    required this.version,
    required this.build,
    required this.url,
    required this.sha256,
    this.notes = '',
  });
  final String version;
  final int build;
  final String url;
  final String sha256;
  final String notes;

  /// null si le manifeste est incomplet ou si le fichier ne vient pas des Releases du dépôt Elikya.
  static Manifeste? lire(Object? json) {
    if (json is! Map) return null;
    final build = json['build'] is int ? json['build'] as int : int.tryParse('${json['build']}');
    final url = '${json['url'] ?? ''}', sha = '${json['sha256'] ?? ''}'.toLowerCase();
    if (build == null || !url.startsWith(depotReleases) || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
    return Manifeste(
      version: '${json['version'] ?? ''}',
      build: build,
      url: url,
      sha256: sha,
      notes: '${json['notes'] ?? ''}',
    );
  }
}

class MiseAJour {
  MiseAJour({http.Client? client, this.manifesteUrl = manifesteParDefaut, this.buildActuel = buildApp})
    : _client = client ?? http.Client();
  final http.Client _client;

  /// Celle de l’application en marche (créée dans main.dart ; absente dans les tests).
  static MiseAJour? instance;
  final String manifesteUrl;
  final int buildActuel;

  /// Version plus récente trouvée (null = l'application est à jour).
  final disponible = ValueNotifier<Manifeste?>(null);

  /// Lit le manifeste ; ne lève jamais d'erreur (pas de réseau = on réessaiera plus tard).
  Future<Manifeste?> verifier() async {
    try {
      final r = await _client
          .get(Uri.parse(manifesteUrl), headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      final m = Manifeste.lire(jsonDecode(utf8.decode(r.bodyBytes)));
      if (m != null && m.build > buildActuel) disponible.value = m;
      return m;
    } catch (e) {
      debugPrint('Mise à jour : vérification impossible ($e)');
      return null;
    }
  }

  /// Télécharge l'installeur dans [dossier] en signalant la progression (0 → 1), puis vérifie
  /// son empreinte. Lève une erreur si le fichier est incomplet ou modifié.
  Future<File> telecharger(Manifeste m, Directory dossier, void Function(double) progres) async {
    final rep = await _client.send(http.Request('GET', Uri.parse(m.url))).timeout(const Duration(minutes: 2));
    if (rep.statusCode != 200) throw Exception('téléchargement refusé (${rep.statusCode})');
    final total = rep.contentLength ?? 0;
    final octets = BytesBuilder(copy: false);
    await for (final morceau in rep.stream.timeout(const Duration(minutes: 2))) {
      octets.add(morceau);
      if (total > 0) progres(octets.length / total);
    }
    final contenu = octets.takeBytes();
    if (sha256.convert(contenu).toString() != m.sha256) {
      throw Exception('le fichier téléchargé est abîmé ou a été modifié (empreinte différente)');
    }
    final f = File('${dossier.path}${Platform.pathSeparator}Elikya-Agents-Setup-${m.version}.exe');
    await f.writeAsBytes(contenu, flush: true);
    return f;
  }

  /// Lance l'installeur en mode silencieux puis ferme l'application ; l'installeur la relance.
  Future<void> installer(File installeur) async {
    await Process.start(installeur.path, ['/S'], mode: ProcessStartMode.detached);
    exit(0);
  }
}
