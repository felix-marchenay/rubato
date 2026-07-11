import 'package:flutter/material.dart';

import '../../domain/lyric_sheet.dart';
import '../theme.dart';
import 'meta_chip.dart';

/// Rendu « paroles + accords » (ChordPro) : chaque accord s'affiche juste
/// au-dessus de la syllabe où il tombe. Sections repérées comme dans la grille.
class LyricSheetView extends StatelessWidget {
  final LyricSheet sheet;
  const LyricSheetView({super.key, required this.sheet});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (sheet.key != null) MetaChip(label: 'TONALITÉ', value: sheet.key!),
      if (sheet.time != null) MetaChip(label: 'MESURE', value: sheet.time!),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chips.isNotEmpty) ...[
                Wrap(spacing: 10, runSpacing: 10, children: chips),
                const SizedBox(height: 24),
              ],
              for (var s = 0; s < sheet.sections.length; s++) ...[
                _SectionBlock(section: sheet.sections[s]),
                if (s != sheet.sections.length - 1) const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final LyricSection section;
  const _SectionBlock({required this.section});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.label != null) ...[
          Row(
            children: [
              Text(section.label!.toUpperCase(), style: RubatoType.caption(p.brass)),
              const SizedBox(width: 12),
              Expanded(child: Container(height: 1, color: p.line)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        for (final line in section.lines) _LyricLineView(line: line),
      ],
    );
  }
}

class _LyricLineView extends StatelessWidget {
  final LyricLine line;
  const _LyricLineView({required this.line});

  @override
  Widget build(BuildContext context) {
    if (line.isBlank) return const SizedBox(height: 14);
    final p = context.palette;

    final chordStyle = RubatoType.serif(
        size: 13, weight: FontWeight.w700, color: p.brass);
    final lyricStyle = TextStyle(fontSize: 16, height: 1.2, color: p.ink);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (final seg in line.segments)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Emplacement d'accord à hauteur fixe : garde l'alignement des
                // paroles même quand un segment n'a pas d'accord.
                SizedBox(
                  height: 18,
                  child: Text(seg.chord ?? '', style: chordStyle),
                ),
                Text(seg.text, style: lyricStyle),
              ],
            ),
        ],
      ),
    );
  }
}
