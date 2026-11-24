import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/audio/practice.dart';
import 'package:mscore/src/codec/chord_parser.dart';
import 'package:mscore/src/domain/chord_chart.dart';
import 'package:mscore/src/ui/theme.dart';
import 'package:mscore/src/ui/widgets/chord_grid_view.dart';

void main() {
  testWidgets('grille en entraînement : surlignage, et un accord touché '
      'renvoie sa position', (tester) async {
    final chart = ChordChart(sections: [
      Section(label: 'A', bars: [
        for (final c in ['C', 'G', 'A-', 'F'])
          Bar([ChordParser.parse(c)]),
        Bar([ChordParser.parse('D-7'), ChordParser.parse('G7')]),
      ]),
    ]);
    ChordRef? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: RubatoTheme.light(),
      home: Scaffold(
        body: ChordGridView(
          chart: chart,
          highlight: GridHighlight(
            current: {(section: 0, bar: 1, chord: 0)},
            done: {(section: 0, bar: 0, chord: 0)},
            reveal: (section: 0, bar: 1, chord: 0),
            onTap: (ref) => tapped = ref,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('G').first);
    expect(tapped, (section: 0, bar: 1, chord: 0));

    // L'exposant de « G7 » (celui de D-7 s'affiche « m7 »).
    await tester.tap(find.text('7'));
    expect(tapped, (section: 0, bar: 4, chord: 1));
  });
}
