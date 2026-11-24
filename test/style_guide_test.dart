import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/audio/practice.dart';
import 'package:mscore/src/codec/chord_parser.dart';
import 'package:mscore/src/data/style_guides.dart';
import 'package:mscore/src/domain/chord_chart.dart';
import 'package:mscore/src/domain/style_guide.dart';
import 'package:mscore/src/ui/style_guide_screen.dart';
import 'package:mscore/src/ui/theme.dart';
import 'package:mscore/src/ui/widgets/chord_symbol.dart';

void main() {
  group('transposeNote', () {
    test('garde la fonction des notes altérées', () {
      expect(transposeNote('Bb', 'C', 'Eb'), 'Db'); // ♭VII
      expect(transposeNote('Bb', 'C', 'E'), 'D');
      expect(transposeNote('Eb', 'C', 'A'), 'C'); // ♭III
      expect(transposeNote('F#', 'C', 'Bb'), 'E'); // #IV
      expect(transposeNote('G#', 'E', 'A'), 'C#'); // tierce de E7
    });

    test('simplifie les orthographes exotiques', () {
      expect(transposeNote('Eb', 'C', 'Db'), 'E'); // pas Fb
      expect(transposeNote('B', 'C', 'C#'), 'C'); // pas B#
    });

    test('identité et notes non reconnues', () {
      expect(transposeNote('F#', 'A', 'A'), 'F#');
      expect(transposeNote('N.C.', 'C', 'D'), 'N.C.');
    });
  });

  test('progression transposée, qualité et basse comprises', () {
    const prog = StyleProgression(
      name: 'test',
      degrees: '',
      bars: ['C G/B', 'A-7 Bb7'],
    );
    final bars = prog.barsIn('C', 'D');
    expect(bars.map((b) => b.chords.map((c) => c.raw).join(' ')),
        ['D A/C#', 'B-7 C7']);
  });

  group('contenu du guide', () {
    test('au moins 20 styles, identifiants uniques', () {
      expect(styleGuides.length, greaterThanOrEqualTo(20));
      expect(styleGuides.map((g) => g.id).toSet().length, styleGuides.length);
    });

    test('fiches complètes et accords tous lisibles', () {
      for (final g in styleGuides) {
        expect(PitchClass.parse(g.tonic), isNotNull, reason: g.id);
        expect(g.timeSignature, isNotNull, reason: g.id);
        expect(g.tempo.min, lessThanOrEqualTo(g.tempo.max), reason: g.id);
        expect(g.progressions, isNotEmpty, reason: g.id);
        for (final list in [g.scales, g.rhythm, g.melody, g.groove, g.sound,
            g.pitfalls, g.artists, g.listen]) {
          expect(list, isNotEmpty, reason: g.id);
        }
        for (final prog in g.progressions) {
          for (final bar in prog.bars) {
            for (final symbol in bar.split(' ')) {
              final chord = ChordParser.parse(symbol);
              final where = '${g.id} / ${prog.name} / $symbol';
              expect(chord.root, isNotNull, reason: where);
              if (chord.bassName != null) {
                expect(chord.bass, isNotNull, reason: where);
              }
              // Jouable en mode entraînement.
              expect(ChordExpectation.of(chord), isNotNull, reason: where);
            }
          }
          for (final t in transposeTonics) {
            final chart = g.chartOf(prog, t);
            for (final c in chart.allBars.expand((b) => b.chords)) {
              expect(c.root, isNotNull, reason: '${g.id} en $t : ${c.raw}');
            }
          }
        }
      }
    });
  });

  testWidgets('fiche : la tonique choisie transpose les progressions',
      (tester) async {
    final blues = styleGuides.firstWhere((g) => g.id == 'blues');
    await tester.pumpWidget(MaterialApp(
      theme: RubatoTheme.light(),
      home: StyleGuideScreen(guide: blues),
    ));
    List<String> firstChords() => tester
        .widgetList<ChordSymbol>(find.byType(ChordSymbol))
        .take(3)
        .map((w) => w.chord.raw)
        .toList();
    expect(firstChords(), ['E7', 'A7', 'E7']);
    await tester.tap(find.text('A').first);
    await tester.pump();
    expect(firstChords(), ['A7', 'D7', 'A7']);
  });
}
