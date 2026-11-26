// Mise à jour à distance : manifeste, comparaison de versions, contrôle d'intégrité, bandeau.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:elikya_agents/data/data_service.dart';
import 'package:elikya_agents/data/local_db.dart';
import 'package:elikya_agents/data/mise_a_jour.dart';
import 'package:elikya_agents/ui/mise_a_jour_ui.dart';
import 'package:elikya_agents/ui/theme.dart';
import 'package:elikya_agents/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_remote.dart';

final installeur = utf8.encode('faux installeur Elikya');
final bonSha = sha256.convert(installeur).toString();
Map<String, Object> manifeste({int build = 99, String? url, String? sha}) => {
  'version': '9.9.9',
  'build': build,
  'url': url ?? '${depotReleases}download/v9.9.9/Elikya-Agents-Setup-9.9.9.exe',
  'sha256': sha ?? bonSha,
  'notes': 'Soldes automatiques.',
};

MiseAJour majAvec(Map<String, Object> m, {List<int>? fichier}) => MiseAJour(
  buildActuel: 8,
  client: MockClient((req) async {
    if (req.url.path.endsWith('agents.json')) return http.Response(jsonEncode(m), 200);
    return http.Response.bytes(fichier ?? installeur, 200);
  }),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('version.dart suit agents/pubspec.yaml (sinon la mise à jour se tromperait de numéro)', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)', multiLine: true).firstMatch(pub)!;
    expect(versionApp, m.group(1));
    expect(buildApp, int.parse(m.group(2)!));
  });

  test('manifeste refusé s’il ne vient pas des Releases Elikya ou si l’empreinte manque', () {
    expect(Manifeste.lire(manifeste()), isNotNull);
    expect(Manifeste.lire(manifeste(url: 'https://exemple.com/virus.exe')), isNull);
    expect(Manifeste.lire(manifeste(sha: 'abc')), isNull);
    expect(Manifeste.lire('pas un objet'), isNull);
  });

  test('nouvelle version proposée seulement si son numéro est plus grand', () async {
    final plusRecente = majAvec(manifeste(build: 9));
    await plusRecente.verifier();
    expect(plusRecente.disponible.value?.version, '9.9.9');

    final pareille = majAvec(manifeste(build: 8));
    await pareille.verifier();
    expect(pareille.disponible.value, isNull);
  });

  test('pas de réseau : aucune erreur, on réessaiera plus tard', () async {
    final maj = MiseAJour(buildActuel: 8, client: MockClient((_) async => throw const SocketException('hors ligne')));
    expect(await maj.verifier(), isNull);
    expect(maj.disponible.value, isNull);
  });

  test('téléchargement : fichier intact accepté, fichier modifié refusé', () async {
    final dossier = await Directory.systemTemp.createTemp('elikya_maj_test');
    addTearDown(() => dossier.delete(recursive: true));
    final m = Manifeste.lire(manifeste())!;
    final progres = <double>[];
    final f = await majAvec(manifeste()).telecharger(m, dossier, progres.add);
    expect(await f.readAsBytes(), installeur);
    expect(progres.last, 1.0);

    final pirate = majAvec(manifeste(), fichier: utf8.encode('autre chose'));
    expect(pirate.telecharger(m, dossier, (_) {}), throwsA(isA<Exception>()));
  });

  testWidgets('bandeau « nouvelle version » puis fenêtre de mise à jour', (t) async {
    final data = DataService(LocalDb(NativeDatabase.memory()), FakeRemote(), probeEvery: const Duration(hours: 1));
    final maj = MiseAJour(buildActuel: 8, client: MockClient((_) async => http.Response('', 404)));
    await t.pumpWidget(
      MaterialApp(
        theme: Elk.theme(Brightness.light),
        home: Scaffold(
          body: BandeauMiseAJour(maj: maj, data: data),
        ),
      ),
    );
    expect(find.textContaining('nouvelle version'), findsNothing, reason: 'rien tant que l’app est à jour');
    maj.disponible.value = Manifeste.lire(manifeste());
    await t.pump();
    expect(find.text('Une nouvelle version de l’application est prête (9.9.9).'), findsOneWidget);
    await t.tap(find.text('Mettre à jour maintenant'));
    await t.pumpAndSettle();
    expect(find.text('Soldes automatiques.'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
    await t.tap(find.text('Plus tard'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await data.local.close();
  });
}
