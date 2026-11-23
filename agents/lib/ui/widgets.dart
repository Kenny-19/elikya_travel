// Briques d'écran communes aux modules (en-tête, KPI, tableau, saisie de montant).
import 'package:flutter/material.dart';

import 'theme.dart';

/// En-tête de module : surtitre doré, titre, sous-titre et actions à droite.
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
          const Text(
            'MODULE · SUIVI',
            style: TextStyle(color: Elk.gold, fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
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
    width: 240,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: Theme.of(context).hintColor, fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
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
