import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/audio/chord_detector.dart';
import 'package:mscore/src/audio/listening_controller.dart';
import 'package:mscore/src/audio/practice.dart';
import 'package:mscore/src/codec/chord_parser.dart';
import 'package:mscore/src/domain/chord_chart.dart';
import 'package:mscore/src/ui/practice_view.dart';
import 'package:mscore/src/ui/theme.dart';

void main() {
  // Accords aux noms longs, sur un téléphone étroit : rien ne doit déborder.
  final session = PracticeSession(practiceSteps(ChordChart(sections: [
    Section(bars: [
      for (final c in ['F#-7b5/C#', 'Bb^7#11', 'Eb7b9#5']) Bar([ChordParser.parse(c)]),
    ]),
  ])));
  final frame = ListeningFrame(
    chroma: Float64List(12),
    levelDb: -30,
    hasSignal: true,
    chord: null,
    tuningCents: 0,
  );

  Future<void> pump(WidgetTester tester, MicStatus status) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: RubatoTheme.light(),
      home: Scaffold(
        body: Column(children: [
          const Spacer(),
          PracticePanel(
            session: session,
            status: status,
            frame: frame,
            gateDb: -55,
            elapsed: const Duration(seconds: 75),
            onToggleMic: () {},
            onRetryMic: () {},
            onRestart: () {},
            onPrevious: () {},
            onNext: () {},
          ),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
  }

  testWidgets('accord à jouer, suivant, progression', (tester) async {
    session.restart();
    await pump(tester, MicStatus.listening);
    expect(find.text('JOUE'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);
  });

  testWidgets('micro refusé', (tester) async {
    await pump(tester, MicStatus.denied);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('grille terminée', (tester) async {
    session.jumpTo(3);
    await pump(tester, MicStatus.listening);
    expect(find.text('Bravo, grille jouée en entier !'), findsOneWidget);
  });
}
