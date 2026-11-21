import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../audio/practice.dart' show ChordRef;
import '../../domain/chord_chart.dart';
import '../chord_format.dart';
import '../theme.dart';
import 'meta_chip.dart';

/// Surlignage du mode entraînement : accord à jouer, accords déjà joués.
class GridHighlight {
  final Set<ChordRef> current;
  final Set<ChordRef> done;

  /// Accord que la grille fait défiler à l'écran quand il change.
  final ChordRef? reveal;
  final ValueChanged<ChordRef>? onTap;

  const GridHighlight({
    this.current = const {},
    this.done = const {},
    this.reveal,
    this.onTap,
  });
}

/// Rendu « grille gravée façon real book » : en-tête (tonalité + mesure),
/// sections marquées d'un repère (A, B…) façon lettre de renvoi, mesures en
/// cases régulières — N par ligne selon la largeur.
class ChordGridView extends StatefulWidget {
  final ChordChart chart;
  final GridHighlight? highlight;
  const ChordGridView({super.key, required this.chart, this.highlight});

  @override
  State<ChordGridView> createState() => _ChordGridViewState();
}

class _ChordGridViewState extends State<ChordGridView> {
  final _revealKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(ChordGridView old) {
    super.didUpdateWidget(old);
    if (old.highlight?.reveal != widget.highlight?.reveal ||
        !setEquals(old.highlight?.current, widget.highlight?.current)) {
      _scheduleReveal();
    }
  }

  void _scheduleReveal() {
    if (widget.highlight?.reveal == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _revealKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  int _barsPerRow(double width) {
    if (width >= 900) return 8; // tablette / paysage large
    if (width >= 600) return 6; // grande tablette portrait
    return 4; // téléphone
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
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
                      sectionIndex: s,
                      barsPerRow: barsPerRow,
                      highlight: widget.highlight,
                      revealKey: _revealKey,
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
      if (chart.key != null) MetaChip(label: 'TONALITÉ', value: '${chart.key}'),
      if (chart.time != null) MetaChip(label: 'MESURE', value: '${chart.time}'),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 10, children: chips);
  }
}

/// Une section : repère (A, B…) + filet, puis la grille de mesures.
class _SectionBlock extends StatelessWidget {
  final Section section;
  final int sectionIndex;
  final int barsPerRow;
  final GridHighlight? highlight;
  final GlobalKey revealKey;
  const _SectionBlock({
    required this.section,
    required this.sectionIndex,
    required this.barsPerRow,
    required this.highlight,
    required this.revealKey,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < section.bars.length; i += barsPerRow) {
      final slice = section.bars.sublist(
        i,
        (i + barsPerRow).clamp(0, section.bars.length),
      );
      rows.add(_BarRow(
        bars: slice,
        barsPerRow: barsPerRow,
        sectionIndex: sectionIndex,
        firstBar: i,
        highlight: highlight,
        revealKey: revealKey,
      ));
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
  final int sectionIndex;
  final int firstBar;
  final GridHighlight? highlight;
  final GlobalKey revealKey;
  const _BarRow({
    required this.bars,
    required this.barsPerRow,
    required this.sectionIndex,
    required this.firstBar,
    required this.highlight,
    required this.revealKey,
  });

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      for (var i = 0; i < bars.length; i++)
        Expanded(
          child: _BarCell(
            bar: bars[i],
            sectionIndex: sectionIndex,
            barIndex: firstBar + i,
            highlight: highlight,
            revealKey: revealKey,
          ),
        ),
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
  final int sectionIndex;
  final int barIndex;
  final GridHighlight? highlight;
  final GlobalKey revealKey;
  const _BarCell({
    required this.bar,
    required this.sectionIndex,
    required this.barIndex,
    required this.highlight,
    required this.revealKey,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = highlight;
    final refs = [
      for (var c = 0; c < bar.chords.length; c++)
        (section: sectionIndex, bar: barIndex, chord: c),
    ];
    final isCurrent = h != null && refs.any(h.current.contains);
    return Container(
      key: h?.reveal != null && refs.contains(h!.reveal) ? revealKey : null,
      constraints: const BoxConstraints(minHeight: 68),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(
          color: isCurrent ? p.brass : p.line,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var c = 0; c < bar.chords.length; c++)
              Flexible(
                child: _tappable(
                  refs[c],
                  _ChordText(
                    chord: bar.chords[c],
                    compact: bar.chords.length > 1,
                    state: h == null
                        ? _ChordState.normal
                        : h.current.contains(refs[c])
                            ? _ChordState.current
                            : h.done.contains(refs[c])
                                ? _ChordState.done
                                : _ChordState.normal,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tappable(ChordRef ref, Widget child) {
    final onTap = highlight?.onTap;
    if (onTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(ref),
      child: child,
    );
  }
}

enum _ChordState { normal, current, done }

/// Accord gravé : racine en serif, qualité en exposant, basse atténuée.
class _ChordText extends StatelessWidget {
  final Chord chord;
  final bool compact;
  final _ChordState state;
  const _ChordText({
    required this.chord,
    required this.compact,
    this.state = _ChordState.normal,
  });

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

    final current = state == _ChordState.current;
    final ink = current ? p.onBrassTint : p.ink;
    final rootStyle = RubatoType.serif(
        size: rootSize, weight: FontWeight.w600, color: ink);
    final qualityStyle = RubatoType.serif(
        size: rootSize * 0.58, weight: FontWeight.w600, color: ink);
    final bassStyle = RubatoType.serif(
        size: rootSize * 0.62, weight: FontWeight.w500, color: p.inkMuted);

    final text = Text.rich(
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
    return switch (state) {
      _ChordState.normal => text,
      _ChordState.done => Opacity(opacity: 0.35, child: text),
      _ChordState.current => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: p.brassTint,
            borderRadius: BorderRadius.circular(6),
          ),
          child: text,
        ),
    };
  }
}
