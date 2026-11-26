// Elikya Agents — application bureau (Windows) des agents.
// Base EN LIGNE Supabase prioritaire, base LOCALE SQLite en secours (cf. lib/data/).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/data_service.dart';
import 'data/local_db.dart';
import 'data/mise_a_jour.dart';
import 'data/remote.dart';
import 'ui/auth_gate.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');

  if (supabaseAnonKey.isEmpty || supabaseAnonKey.startsWith('COLLE_TA')) {
    runApp(const _ConfigMissingApp());
    return;
  }

  // Restaure la session mémorisée même sans réseau (le rafraîchissement du jeton
  // se refera tout seul au retour de la connexion).
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  } catch (e) {
    debugPrint('Supabase.initialize : $e');
  }

  final data = DataService(LocalDb(), SupabaseRemote(Supabase.instance.client));
  await data.refreshCounts();
  MiseAJour.instance = MiseAJour(); // mise à jour à distance (lib/data/mise_a_jour.dart)
  runApp(ElikyaAgentsApp(data: data));
}

class ElikyaAgentsApp extends StatelessWidget {
  const ElikyaAgentsApp({super.key, required this.data});
  final DataService data;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Elikya Agents',
    debugShowCheckedModeBanner: false,
    theme: Elk.theme(Brightness.light),
    darkTheme: Elk.theme(Brightness.dark),
    locale: const Locale('fr', 'FR'),
    supportedLocales: const [Locale('fr', 'FR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: AuthGate(data: data),
  );
}

class _ConfigMissingApp extends StatelessWidget {
  const _ConfigMissingApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: Elk.theme(Brightness.light),
    home: const Scaffold(
      body: Center(
        child: Text(
          'Configuration manquante : copie lib/config.example.dart en lib/config.dart\n'
          'et colle ta clé anon Supabase, puis relance l\'application.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
