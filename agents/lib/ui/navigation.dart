// Navigation simple entre modules : l'accueil demande « va dans tel module et fais telle action »
// (ex. ('location', 'louer') ouvre Location et son formulaire « Louer »).
// La coque (shell.dart) change de module ; la page appelle prendreAction() une fois chargée.
import 'package:flutter/foundation.dart';

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
