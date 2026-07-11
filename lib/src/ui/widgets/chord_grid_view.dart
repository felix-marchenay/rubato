import 'package:flutter/material.dart';

import '../../domain/chord_chart.dart';
import '../chord_format.dart';
import '../theme.dart';

/// Rendu « grille gravée façon real book » : en-tête (tonalité + mesure),
/// sections marquées d'un repère (A, B…) façon lettre de renvoi, mesures en
/// cases régulières — N par ligne selon la largeur.
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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ChartHeader(chart: chart),
                  const SizedBox(height: 24),
                  for (var s = 0; s < chart.sections.length; s++) ...[
                    _SectionBlock(
                      section: chart.sections[s],
                      barsPerRow: barsPerRow,
                    ),
                    if (s != chart.sections.length - 1)
                      const SizedBox(height: 28),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ligne de méta : tonalité et mesure, en petites étiquettes encadrées.
class _ChartHeader extends StatelessWidget {
  final ChordChart chart;
  const _ChartHeader({required this.chart});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (chart.key != null) _MetaChip(label: 'TONALITÉ', value: '${chart.key}'),
      if (chart.time != null) _MetaChip(label: 'MESURE', value: '${chart.time}'),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 10, children: chips);
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;
  const _MetaChip({required this.label, required this.value});

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

/// Une section : repère (A, B…) + filet, puis la grille de mesures.
class _SectionBlock extends StatelessWidget {
  final Section section;
  final int barsPerRow;
  const _SectionBlock({required this.section, required this.barsPerRow});

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
      children: [
        if (section.label != null) ...[
          _SectionMark(label: section.label!),
          const SizedBox(height: 10),
        ],
        ...rows,
      ],
    );
  }
}

/// Repère de section en pastille laiton, suivi d'un filet — lettre de renvoi.
class _SectionMark extends StatelessWidget {
  final String label;
  const _SectionMark({required this.label});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.brassTint,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: RubatoType.serif(
                size: 14, weight: FontWeight.w700, color: p.onBrassTint),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: p.line)),
      ],
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
    // IntrinsicHeight borne la hauteur de la ligne (= case la plus haute) : sans
    // lui, `CrossAxisAlignment.stretch` reçoit une hauteur infinie (Row imbriqué
    // dans un SingleChildScrollView vertical) et fait planter le layout.
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
    );
  }
}

class _BarCell extends StatelessWidget {
  final Bar bar;
  const _BarCell({required this.bar});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final chord in bar.chords)
              Flexible(
                child: _ChordText(
                  chord: chord,
                  compact: bar.chords.length > 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Accord gravé : racine en serif, qualité en exposant, basse atténuée.
class _ChordText extends StatelessWidget {
  final Chord chord;
  final bool compact;
  const _ChordText({required this.chord, required this.compact});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final parts = ChordFormat.parts(chord);
    final rootSize = compact ? 17.0 : 22.0;

    if (parts.isNoChord) {
      return Text(
        'N.C.',
        textAlign: TextAlign.center,
        style: RubatoType.serif(
          size: rootSize * 0.8,
          weight: FontWeight.w500,
          color: p.inkMuted,
          style: FontStyle.italic,
        ),
      );
    }

    final rootStyle = RubatoType.serif(
        size: rootSize, weight: FontWeight.w600, color: p.ink);
    final qualityStyle = RubatoType.serif(
        size: rootSize * 0.58, weight: FontWeight.w600, color: p.ink);
    final bassStyle = RubatoType.serif(
        size: rootSize * 0.62, weight: FontWeight.w500, color: p.inkMuted);

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
