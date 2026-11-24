import 'package:flutter/material.dart';

import '../domain/chord_chart.dart';
import '../domain/style_guide.dart';
import 'practice_view.dart';
import 'theme.dart';
import 'widgets/chord_symbol.dart';

/// Fiche d'un style, à lire d'un coup d'œil : repères (tempo, mesure…),
/// progressions transposables, puis conseils de jeu.
class StyleGuideScreen extends StatefulWidget {
  final StyleGuide guide;
  const StyleGuideScreen({super.key, required this.guide});

  @override
  State<StyleGuideScreen> createState() => _StyleGuideScreenState();
}

class _StyleGuideScreenState extends State<StyleGuideScreen> {
  late String _tonic = widget.guide.tonic;

  void _practice(StyleProgression progression) {
    final g = widget.guide;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PracticeScreen(
        title: progression.name,
        subtitle: '${g.name} · tonique $_tonic',
        chart: g.chartOf(progression, _tonic),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = widget.guide;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Text(
          g.name,
          style: RubatoType.serif(size: 20, weight: FontWeight.w600, color: p.ink),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              _Header(guide: g),
              const SizedBox(height: 18),
              _Facts(guide: g),
              _Section(
                title: 'Progressions',
                trailing: _TonicPicker(
                  value: _tonic,
                  usual: g.tonic,
                  onChanged: (t) => setState(() => _tonic = t),
                ),
                child: Column(
                  children: [
                    for (final prog in g.progressions)
                      _ProgressionCard(
                        progression: prog,
                        bars: prog.barsIn(g.tonic, _tonic),
                        onPractice: () => _practice(prog),
                      ),
                  ],
                ),
              ),
              _Section(title: 'Gammes', child: _Pills(g.scales, accent: true)),
              _Section(title: 'Accompagnement', child: _Bullets(g.rhythm)),
              _Section(title: 'Mélodie & impro', child: _Bullets(g.melody)),
              _Section(title: 'Basse & batterie', child: _Bullets(g.groove)),
              _Section(title: 'Le son', child: _Pills(g.sound)),
              _Section(
                title: 'À éviter',
                child: _Bullets(g.pitfalls, marker: Icons.close),
              ),
              _Section(title: 'Références', child: _Pills(g.artists)),
              _Section(
                title: 'À écouter',
                child: _Bullets(g.listen, marker: Icons.play_arrow_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final StyleGuide guide;
  const _Header({required this.guide});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(guide.family.label.toUpperCase(), style: RubatoType.caption(p.brass)),
        const SizedBox(height: 6),
        Text(
          guide.tagline,
          style: RubatoType.serif(
            size: 21,
            weight: FontWeight.w500,
            color: p.ink,
            style: FontStyle.italic,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(guide.origin, style: TextStyle(fontSize: 12.5, color: p.inkMuted)),
      ],
    );
  }
}

/// Repères en cases : tempo (avec jauge), mesure, placement, tonalités.
class _Facts extends StatelessWidget {
  final StyleGuide guide;
  const _Facts({required this.guide});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 10.0;
      final half = (constraints.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(
            width: constraints.maxWidth,
            child: _FactCard(
              label: 'TEMPO',
              value: '${guide.tempo} BPM',
              extra: _TempoGauge(range: guide.tempo),
            ),
          ),
          SizedBox(width: half, child: _FactCard(label: 'MESURE', value: guide.meter)),
          SizedBox(
            width: half,
            child: _FactCard(label: 'TONALITÉS', value: guide.keys.join(' · ')),
          ),
          SizedBox(
            width: constraints.maxWidth,
            child: _FactCard(label: 'PLACEMENT', value: guide.feel),
          ),
        ],
      );
    });
  }
}

class _FactCard extends StatelessWidget {
  final String label;
  final String value;
  final Widget? extra;
  const _FactCard({required this.label, required this.value, this.extra});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: RubatoType.caption(p.inkMuted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: RubatoType.serif(size: 16, weight: FontWeight.w600, color: p.ink),
          ),
          if (extra != null) ...[const SizedBox(height: 10), extra!],
        ],
      ),
    );
  }
}

/// Plage de tempo posée sur une échelle lente → rapide.
class _TempoGauge extends StatelessWidget {
  final TempoRange range;
  const _TempoGauge({required this.range});

  static const _min = 40.0;
  static const _max = 320.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    double at(int bpm) => ((bpm - _min) / (_max - _min)).clamp(0.0, 1.0);
    final small = TextStyle(fontSize: 10.5, color: p.inkMuted);
    return Column(
      children: [
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final left = at(range.min) * w;
          final width = (at(range.max) * w - left).clamp(6.0, w);
          return SizedBox(
            height: 8,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.brassTint,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Positioned(
                  left: left,
                  width: width,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.brass,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('lent', style: small),
            Text('modéré', style: small),
            Text('rapide', style: small),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title.toUpperCase(), style: RubatoType.caption(p.brass)),
              const SizedBox(width: 12),
              Expanded(child: Container(height: 1, color: p.line)),
            ],
          ),
          if (trailing != null) ...[const SizedBox(height: 10), trailing!],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Choix de la tonique : les progressions sont transposées à la volée.
class _TonicPicker extends StatelessWidget {
  final String value;
  final String usual;
  final ValueChanged<String> onChanged;
  const _TonicPicker({required this.value, required this.usual, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text('TONIQUE', style: RubatoType.caption(p.inkMuted)),
          const SizedBox(width: 10),
          for (final t in transposeTonics)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => onChanged(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t == value ? p.brass : Colors.transparent,
                    border: Border.all(color: t == usual ? p.brass : p.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    t,
                    style: RubatoType.serif(
                      size: 14,
                      weight: FontWeight.w600,
                      color: t == value ? p.onBrass : p.ink,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressionCard extends StatelessWidget {
  final StyleProgression progression;
  final List<Bar> bars;
  final VoidCallback onPractice;
  const _ProgressionCard({
    required this.progression,
    required this.bars,
    required this.onPractice,
  });

  static const _barsPerRow = 4;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = <Widget>[
      for (var i = 0; i < bars.length; i += _barsPerRow)
        // IntrinsicHeight : Row étiré dans une liste verticale (cf. _BarRow).
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = i; j < i + _barsPerRow; j++)
                Expanded(
                  child: j < bars.length ? _BarCell(bar: bars[j]) : const SizedBox(),
                ),
            ],
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progression.name,
                      style: RubatoType.serif(size: 17, weight: FontWeight.w600, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progression.degrees,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: p.onBrassTint,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onPractice,
                icon: const Icon(Icons.graphic_eq),
                color: p.brass,
                tooltip: 'S\'entraîner sur cette progression',
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rows,
          if (progression.tip != null) ...[
            const SizedBox(height: 6),
            Text(
              progression.tip!,
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: p.inkMuted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarCell extends StatelessWidget {
  final Bar bar;
  const _BarCell({required this.bar});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final compact = bar.chords.length > 1;
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final chord in bar.chords)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ChordSymbol(chord: chord, size: compact ? 15 : 19),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bullets extends StatelessWidget {
  final List<String> items;
  final IconData? marker;
  const _Bullets(this.items, {this.marker});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: marker == null
                        ? Text('—', style: TextStyle(color: p.brass, fontWeight: FontWeight.w700))
                        : Icon(marker, size: 15, color: p.brass),
                  ),
                ),
                Expanded(
                  child: Text(item, style: TextStyle(fontSize: 14, color: p.ink, height: 1.4)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Pills extends StatelessWidget {
  final List<String> items;
  final bool accent;
  const _Pills(this.items, {this.accent = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accent ? p.brassTint : null,
              border: accent ? null : Border.all(color: p.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent ? p.onBrassTint : p.ink,
              ),
            ),
          ),
      ],
    );
  }
}

/// Entraînement au micro sur une progression du guide.
class _PracticeScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final ChordChart chart;
  const _PracticeScreen({required this.title, required this.subtitle, required this.chart});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: RubatoType.serif(size: 19, weight: FontWeight.w600, color: p.ink),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: p.inkMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
        ),
      ),
      body: PracticeView(chart: chart),
    );
  }
}
