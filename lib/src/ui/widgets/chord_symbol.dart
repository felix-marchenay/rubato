import 'package:flutter/material.dart';

import '../../domain/chord_chart.dart';
import '../chord_format.dart';
import '../theme.dart';

/// Accord gravé : racine en serif, qualité en exposant, basse atténuée.
class ChordSymbol extends StatelessWidget {
  final Chord chord;
  final double size;

  /// Encre de la racine et de la qualité (défaut : encre du thème).
  final Color? color;

  const ChordSymbol({super.key, required this.chord, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final parts = ChordFormat.parts(chord);

    if (parts.isNoChord) {
      return Text(
        'N.C.',
        textAlign: TextAlign.center,
        style: RubatoType.serif(
          size: size * 0.8,
          weight: FontWeight.w500,
          color: p.inkMuted,
          style: FontStyle.italic,
        ),
      );
    }

    final ink = color ?? p.ink;
    final rootStyle =
        RubatoType.serif(size: size, weight: FontWeight.w600, color: ink);
    final qualityStyle =
        RubatoType.serif(size: size * 0.58, weight: FontWeight.w600, color: ink);
    final bassStyle = RubatoType.serif(
        size: size * 0.62, weight: FontWeight.w500, color: p.inkMuted);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: parts.root, style: rootStyle),
          if (parts.quality.isNotEmpty)
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Padding(
                padding: const EdgeInsets.only(left: 1),
                child: Text(parts.quality, style: qualityStyle),
              ),
            ),
          if (parts.bass != null)
            TextSpan(text: '/${parts.bass}', style: bassStyle),
        ],
      ),
      textAlign: TextAlign.center,
      overflow: TextOverflow.visible,
    );
  }
}
