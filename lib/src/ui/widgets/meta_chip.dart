import 'package:flutter/material.dart';

import '../theme.dart';

/// Petite étiquette encadrée « LABEL valeur » (tonalité, mesure…), partagée
/// entre la grille d'accords et la feuille paroles.
class MetaChip extends StatelessWidget {
  final String label;
  final String value;
  const MetaChip({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: RubatoType.caption(p.inkMuted)),
          const SizedBox(width: 8),
          Text(
            value,
            style: RubatoType.serif(
                size: 15, weight: FontWeight.w600, color: p.ink),
          ),
        ],
      ),
    );
  }
}
