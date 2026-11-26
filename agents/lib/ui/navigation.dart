// Navigation simple entre modules : l'accueil demande « va dans tel module et fais telle action »
// (ex. ('location', 'louer') ouvre Location et son formulaire « Louer »).
// La coque (shell.dart) change de module ; la page appelle prendreAction() une fois chargée.
import 'package:flutter/widgets.dart';

class Navigation {
  static final demande = ValueNotifier<(String, String?)?>(null);

  /// Ouvre [module] et, si [action] est donnée, la page la déclenche (une seule fois).
  static void aller(String module, [String? action]) => demande.value = (module, action);

  /// À appeler par une page après son chargement : renvoie l'action demandée pour elle, puis l'oublie.
  static String? prendreAction(String module) {
    final d = demande.value;
    if (d == null || d.$1 != module || d.$2 == null) return null;
    demande.value = (module, null);
    return d.$2;
  }
}

/// Mise à jour automatique des écrans : la coque (shell.dart) fait « tic » toutes les 30 secondes,
/// chaque page relit la base SANS sablier (ce que les collègues ont saisi apparaît tout seul).
class Rafraichir {
  static final tick = ValueNotifier<int>(0);
}

/// À ajouter aux pages : `with AutoRafraichi` + `void rafraichir() => _load(silencieux: true);`.
/// Rien ne se passe pendant qu'une fenêtre de saisie est ouverte par-dessus la page.
mixin AutoRafraichi<T extends StatefulWidget> on State<T> {
  void rafraichir();

  @override
  void initState() {
    super.initState();
    Rafraichir.tick.addListener(_tic);
  }

  @override
  void dispose() {
    Rafraichir.tick.removeListener(_tic);
    super.dispose();
  }

  void _tic() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return; // une boîte de dialogue est ouverte
    rafraichir();
  }
}
