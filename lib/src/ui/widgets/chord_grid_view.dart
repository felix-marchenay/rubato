import 'package:flutter/material.dart';

import '../../domain/chord_chart.dart';
import '../chord_format.dart';

/// Rendu « grille fixe façon iReal Pro » : mesures en cases régulières,
/// N mesures par ligne (adapté à la largeur), chaque section démarre une
/// nouvelle ligne. Tonalité + signature rythmique en tête.
class ChordGridView extends StatelessWidget {
  final ChordChart chart;
  const ChordGridView({super.key, required this.chart});

  int _barsPerRow(double width) {
    if (width >= 900) return 8; // tablette / paysage large
    if (width >= 600) return 6; // grande tablette portrait
    return 4; // téléphone
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final barsPerRow = _barsPerRow(constraints.maxWidth);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ChartHeader(chart: chart),
              const SizedBox(height: 16),
              for (final section in chart.sections) ...[
                _SectionGrid(section: section, barsPerRow: barsPerRow),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ChartHeader extends StatelessWidget {
  final ChordChart chart;
  const _ChartHeader({required this.chart});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (chart.key != null) _pill(context, 'Tonalité ${chart.key}'),
      if (chart.time != null) _pill(context, 'Mesure ${chart.time}'),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _pill(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SectionGrid extends StatelessWidget {
  final Section section;
  final int barsPerRow;
  const _SectionGrid({required this.section, required this.barsPerRow});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < section.bars.length; i += barsPerRow) {
      final slice = section.bars.sublist(
        i,
        (i + barsPerRow).clamp(0, section.bars.length),
      );
      rows.add(_BarRow(bars: slice, barsPerRow: barsPerRow));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _BarRow extends StatelessWidget {
  final List<Bar> bars;
  final int barsPerRow;
  const _BarRow({required this.bars, required this.barsPerRow});

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      for (final bar in bars) Expanded(child: _BarCell(bar: bar)),
      // Cases vides pour aligner la dernière ligne.
      for (var i = bars.length; i < barsPerRow; i++)
        const Expanded(child: SizedBox()),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells);
  }
}

class _BarCell extends StatelessWidget {
  final Bar bar;
  const _BarCell({required this.bar});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final chord in bar.chords)
              Flexible(
                child: Text(
                  ChordFormat.display(chord),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: bar.chords.length > 1 ? 15 : 18,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
