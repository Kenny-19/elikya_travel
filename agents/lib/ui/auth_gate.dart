// Connexion + contrôle du rôle.
// - Session Supabase mémorisée sur le poste → l'agent peut travailler hors ligne.
// - Le rôle vient de rpc('mon_profil') (db/roles.sql) ; hors ligne, du dernier profil connu.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/data_service.dart';
import '../data/remote.dart';
import '../profile.dart';
import 'modules.dart';
import 'shell.dart';
import 'theme.dart';

enum _Phase { loading, login, denied, ready }

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.data});
  final DataService data;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _Phase phase = _Phase.loading;
  Profile? profile;
  String message = '';
  StreamSubscription<AuthState>? _sub;

  SupabaseClient get _auth => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _sub = _auth.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut && mounted) setState(() => phase = _Phase.login);
    }, onError: (_) {});
    _check();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => phase = _Phase.loading);
    final user = _auth.auth.currentSession?.user;
    if (user == null) return setState(() => phase = _Phase.login);

    Profile? p;
    try {
      final j = await widget.data.rpc('mon_profil');
      if (j == null) {
        return _deny(
          "Ce compte n'est relié à aucune fiche employé active.\n"
          "Demande à la direction de l'ajouter dans la table users (même e-mail).",
        );
      }
      p = Profile.fromJson(Map<String, dynamic>.from(j as Map));
      await widget.data.saveProfile(user.id, p.toJson());
    } on RemoteNetworkError {
      widget.data.goOffline();
      final c = await widget.data.cachedProfile(user.id);
      if (c == null) return _deny('Pas de connexion : la première connexion de ce poste doit se faire avec internet.');
      p = Profile.fromJson(c);
    } on RemoteError catch (e) {
      if (e.code == 'PGRST202' || e.message.contains('mon_profil')) {
        return _deny('Rôles non installés : exécute db/roles.sql dans Supabase (SQL Editor).');
      }
      return _deny('Erreur : ${e.message}');
    }

    if (!modules.any((m) => p!.can(m.perm))) {
      return _deny('Aucun module n\'est ouvert pour le rôle « ${p.role} ».');
    }
    setState(() {
      profile = p;
      phase = _Phase.ready;
    });
    unawaited(widget.data.sync().then((_) => widget.data.warmup()));
  }

  void _deny(String m) => setState(() {
    message = m;
    phase = _Phase.denied;
  });

  Future<void> _signOut() async {
    try {
      await _auth.auth.signOut();
    } catch (_) {
      // hors ligne : la session locale est quand même effacée
    }
    if (mounted) setState(() => phase = _Phase.login);
  }

  @override
  Widget build(BuildContext context) => switch (phase) {
    _Phase.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
    _Phase.login => LoginPage(onLoggedIn: _check),
    _Phase.denied => _Centered(
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 18),
        OutlinedButton(onPressed: _signOut, child: const Text('Se déconnecter')),
      ],
    ),
    _Phase.ready => Shell(data: widget.data, profile: profile!, onSignOut: _signOut),
  };
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLoggedIn});
  final VoidCallback onLoggedIn;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool busy = false;
  String error = '';

  Future<void> _login() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: _email.text.trim(), password: _pass.text)
          .timeout(const Duration(seconds: 10));
      widget.onLoggedIn();
    } on AuthRetryableFetchException {
      setState(() => error = 'Pas de connexion internet : impossible de se connecter.');
    } on AuthException catch (e) {
      setState(() => error = 'Échec : ${e.message}');
    } catch (_) {
      setState(() => error = 'Pas de connexion internet : impossible de se connecter.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Centered(
    children: [
      const _Brand(),
      const SizedBox(height: 22),
      TextField(
        controller: _email,
        decoration: const InputDecoration(labelText: 'E-mail'),
        autofocus: true,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pass,
        decoration: const InputDecoration(labelText: 'Mot de passe'),
        obscureText: true,
        onSubmitted: (_) => busy ? null : _login(),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: busy ? null : _login, child: Text(busy ? 'Connexion…' : 'Se connecter')),
      ),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(error, style: const TextStyle(color: Elk.crit)),
        ),
    ],
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Elk.gold2, width: 1.5),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Text(
          'E',
          style: TextStyle(color: Elk.gold2, fontSize: 24, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(width: 12),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Elikya', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text('AGENTS', style: TextStyle(fontSize: 10.5, letterSpacing: 2.4)),
        ],
      ),
    ],
  );
}

class _Centered extends StatelessWidget {
  const _Centered({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 380,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 26),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    ),
  );
}
