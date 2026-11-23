// Thème aux couleurs de la charte Elikya Group — mêmes valeurs que web/assets/styles.css.
// Marine profond #0B1F3A (dominant) · marine secondaire #16325C · orange #F2882A (accent ≤ 10 %)
// · gris-bleu #EEF2F7 · texte secondaire #5B6B82 · police Plus Jakarta Sans (intégrée).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Elk {
  // --- charte ---
  static const navy = Color(0xFF0B1F3A); // marine profond
  static const navy2 = Color(0xFF16325C); // marine secondaire
  static const accent = Color(0xFFF2882A); // orange (boutons d'action, repère actif)
  static const accentText = Color(0xFFB45A0C); // orange lisible en petit texte sur fond clair
  static const mist = Color(0xFFEEF2F7); // gris-bleu clair (fond)
  static const slate = Color(0xFF5B6B82); // texte secondaire
  static const line = Color(0xFFDDE3EC);

  // --- barre latérale ---
  static const side = navy;
  static const side2 = navy2;
  static const sideInk = Color(0xFFE6ECF5);
  static const sideMuted = Color(0xFFAEC2E2);

  // --- statuts (distincts de l'orange de marque) ---
  static const ok = Color(0xFF1F7A4D);
  static const warn = Color(0xFF9A6100);
  static const crit = Color(0xFFC0392B);
  static const info = Color(0xFF1D5FA8);

  static const font = 'PlusJakartaSans';

  static ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    final ink = dark ? const Color(0xFFEEF2F7) : navy;
    final muted = dark ? sideMuted : slate;
    final surface = dark ? navy : Colors.white;
    final lineC = dark ? const Color(0xFF1D3A66) : line;
    final scheme = ColorScheme.fromSeed(
      seedColor: navy,
      brightness: b,
      primary: dark ? accent : navy,
      onPrimary: dark ? navy : Colors.white,
      secondary: accent,
      onSecondary: navy,
      surface: surface,
      onSurface: ink,
      error: dark ? const Color(0xFFF07163) : crit,
    );
    final base = ThemeData(brightness: b, fontFamily: font);
    return ThemeData(
      colorScheme: scheme,
      fontFamily: font,
      scaffoldBackgroundColor: dark ? const Color(0xFF071831) : mist,
      hintColor: muted,
      dividerColor: lineC,
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: lineC),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: dark ? const Color(0xFF112A4D) : const Color(0xFFF5F7FB),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: lineC),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: lineC),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.6),
        ),
      ),
      // Bouton d'action principal = orange, texte marine (contraste 7:1), comme le site
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: navy,
          disabledBackgroundColor: accent.withValues(alpha: .35),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: lineC),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? accent : navy2,
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? ink : null),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? surface : ink),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: font, fontWeight: FontWeight.w700)),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(dark ? const Color(0xFF112A4D) : const Color(0xFFF5F7FB)),
        headingTextStyle: TextStyle(
          fontFamily: font,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
          color: muted,
        ),
        dataTextStyle: TextStyle(fontFamily: font, fontSize: 13, color: ink),
        dividerThickness: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: navy,
        contentTextStyle: TextStyle(fontFamily: font, color: Colors.white, fontWeight: FontWeight.w500),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 19, fontWeight: FontWeight.w800, color: ink),
      ),
    );
  }

  static final _num = NumberFormat.decimalPattern('fr_FR');
  static String fmt(Object? n) => _num.format(n is num ? n : (double.tryParse('$n') ?? 0));
  static String money(Object? n, String? code) => '${fmt(n)} ${code == 'CDF' ? 'FC' : '\$'}';
}

/// Logo officiel Elikya Group : emblème (PNG rendu fidèlement depuis elikya-mark.svg)
/// + mot-symbole ELIKYA (marine ou blanc) GROUP (orange).
class ElikyaLogo extends StatelessWidget {
  const ElikyaLogo({super.key, this.size = 40, this.onDark = false, this.subtitle});
  final double size;
  final bool onDark;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(size * .23),
        child: Image.asset('assets/brand/mark-512.png', width: size, height: size, filterQuality: FilterQuality.medium),
      ),
      SizedBox(width: size * .3),
      // le mot-symbole se réduit plutôt que de déborder si la place manque
      Flexible(
        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _wordmark()),
      ),
    ],
  );

  Widget _wordmark() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'ELIKYA ',
              style: TextStyle(color: onDark ? Colors.white : const Color(0xFF123C7B)),
            ),
            const TextSpan(
              text: 'GROUP',
              style: TextStyle(color: Elk.accent),
            ),
          ],
        ),
        style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.w800, letterSpacing: .3, height: 1),
      ),
      if (subtitle != null) ...[
        SizedBox(height: size * .12),
        Text(
          subtitle!.toUpperCase(),
          style: TextStyle(
            fontSize: (size * .22).clamp(9, 12).toDouble(),
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: onDark ? Elk.sideMuted : Elk.slate,
          ),
        ),
      ],
    ],
  );
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
