// Thème graphite & doré — mêmes couleurs que web/assets/styles.css.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Elk {
  static const gold = Color(0xFFA9792A);
  static const gold2 = Color(0xFFCAA24E);
  static const side = Color(0xFF17181A);
  static const side2 = Color(0xFF1F2023);
  static const sideInk = Color(0xFFCFCDC6);
  static const sideMuted = Color(0xFF86847D);
  static const ok = Color(0xFF2F8255);
  static const warn = Color(0xFFB4791A);
  static const crit = Color(0xFFB5402B);
  static const info = Color(0xFF2F6A9C);

  static ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: gold,
      brightness: b,
      primary: dark ? const Color(0xFFCDA352) : gold,
      surface: dark ? const Color(0xFF1B1C1F) : Colors.white,
      error: dark ? const Color(0xFFDD6B53) : crit,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF121315) : const Color(0xFFF1F1EC),
      fontFamily: 'Segoe UI',
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: dark ? const Color(0xFF2B2C30) : const Color(0xFFE4E1D8)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }

  static final _num = NumberFormat.decimalPattern('fr_FR');
  static String fmt(Object? n) => _num.format(n is num ? n : (double.tryParse('$n') ?? 0));
  static String money(Object? n, String? code) => '${fmt(n)} ${code == 'CDF' ? 'FC' : '\$'}';
}

/// Pastille de statut (équivalent de Elikya.h.pill).
class Pill extends StatelessWidget {
  const Pill(this.label, this.color, {super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

/// Suffixe de message quand une saisie a été gardée en local.
String savedSuffix(bool offline) => offline ? ' · hors ligne, sera synchronisé' : ' ✓';
