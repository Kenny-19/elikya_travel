// Briques d'écran communes aux modules (en-tête, KPI, tableau, saisie de montant).
import 'package:flutter/material.dart';

import 'theme.dart';

/// En-tête de module : surtitre orange (capitales espacées), titre ExtraBold, sous-titre, actions.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, required this.subtitle, this.actions = const []});
  final String title, subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 12,
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.end,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MODULE · SUIVI',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF6A25A) : Elk.accentText,
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.5)),
          Text(subtitle, style: TextStyle(color: Theme.of(context).hintColor)),
        ],
      ),
      Wrap(spacing: 10, runSpacing: 10, children: actions),
    ],
  );
}

class Kpi extends StatelessWidget {
  const Kpi(this.label, this.value, {super.key, this.footer});
  final String label, value;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 228, // 4 tuiles sur une ligne dès 1280 px de large
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: Theme.of(context).hintColor, fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            if (footer != null) ...[const SizedBox(height: 6), footer!],
          ],
        ),
      ),
    ),
  );
}

/// Tableau dans une carte, avec états chargement / vide.
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.loading, required this.empty, required this.columns, required this.rows});
  final bool loading;
  final String empty;
  final List<DataColumn> columns;
  final List<DataRow> rows;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: loading
        ? const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        : rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(30),
            child: Center(
              child: Text(empty, style: TextStyle(color: Theme.of(context).hintColor)),
            ),
          )
        : SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(columns: columns, rows: rows),
            ),
          ),
  );
}

/// Montant saisi « 1 250,50 » ou « 1250.5 » → nombre (null si invalide).
double? parseAmount(String? v) => double.tryParse((v ?? '').replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));

/// Champ de montant avec contrôle (> 0 par défaut).
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.allowZero = false,
    this.required = true,
  });
  final TextEditingController controller;
  final String label;
  final bool allowZero, required;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: (v) {
      if (!required && (v ?? '').trim().isEmpty) return null;
      final n = parseAmount(v);
      if (n == null || n < 0 || (!allowZero && n == 0)) return 'Montant invalide';
      return null;
    },
  );
}

/// Liste déroulante de formulaire, typée.
Widget dropdown<T>(String label, T value, Map<T, String> items, ValueChanged<T?> onChanged) =>
    DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );

/// Grille de formulaire à 2 colonnes dans une boîte de dialogue.
Widget formGrid(List<Widget> fields) =>
    Wrap(spacing: 14, runSpacing: 14, children: [for (final f in fields) SizedBox(width: 253, child: f)]);

void toast(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar() // le nouveau message remplace l'ancien tout de suite
  ..showSnackBar(SnackBar(content: Text(message)));

// ------------------------------------------------------------------ éléments « simples » (Location, Voyage…)
class TitreSection extends StatelessWidget {
  const TitreSection(this.texte, {super.key});
  final String texte;
  @override
  Widget build(BuildContext context) => Text(texte, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
}

class Compteur extends StatelessWidget {
  const Compteur(this.icone, this.couleur, this.valeur, this.libelle, {super.key});
  final IconData icone;
  final Color couleur;
  final String valeur, libelle;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, color: couleur, size: 26),
          const SizedBox(width: 12),
          Text(valeur, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text(
            libelle,
            style: TextStyle(color: Theme.of(context).hintColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class Bandeau extends StatelessWidget {
  const Bandeau({super.key, required this.couleur, required this.icone, required this.texte, this.details = const []});
  final Color couleur;
  final IconData icone;
  final String texte;
  final List<String> details;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: couleur.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: couleur.withValues(alpha: .35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, color: couleur),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                texte,
                style: TextStyle(color: couleur, fontWeight: FontWeight.w800),
              ),
              for (final d in details) Padding(padding: const EdgeInsets.only(top: 4), child: Text(d)),
            ],
          ),
        ),
      ],
    ),
  );
}

class EtatVide extends StatelessWidget {
  const EtatVide({super.key, required this.icone, required this.texte, this.bouton});
  final IconData icone;
  final String texte;
  final Widget? bouton;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          children: [
            Icon(icone, size: 40, color: Theme.of(context).hintColor),
            const SizedBox(height: 10),
            Text(texte, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 15)),
            if (bouton != null) ...[const SizedBox(height: 14), bouton!],
          ],
        ),
      ),
    ),
  );
}

/// Carte d'un véhicule : état en couleur + UN bouton principal adapté à la situation.
class Etape extends StatelessWidget {
  const Etape(this.numero, this.titre, {super.key});
  final String numero, titre;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: Elk.navy,
          child: Text(
            numero,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Text(titre, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
