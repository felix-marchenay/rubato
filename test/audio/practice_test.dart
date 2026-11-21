import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/audio/chord_detector.dart';
import 'package:mscore/src/audio/practice.dart';
import 'package:mscore/src/codec/chord_parser.dart';
import 'package:mscore/src/domain/chord_chart.dart';

import 'synth.dart';

ChordChart chart(List<List<List<String>>> sections) => ChordChart(sections: [
      for (final bars in sections)
        Section(bars: [
          for (final bar in bars) Bar([for (final c in bar) ChordParser.parse(c)]),
        ]),
    ]);

/// Joue [signal] devant une session ; renvoie l'instant (s) de chaque
/// validation.
List<double> play(PracticeSession session, Float64List signal) {
  final detector = ChordDetector(sampleRate: 44100);
  final validations = <double>[];
  const chunk = 2048;
  for (var i = 0; i < signal.length; i += chunk) {
    final end = (i + chunk).clamp(0, signal.length);
    for (final f in detector.add(signal.sublist(i, end))) {
      if (session.onFrame(f)) validations.add(end / 44100);
    }
  }
  return validations;
}

void main() {
  group('familles d\'accords', () {
    const cases = {
      '': ChordFamily.major, '7': ChordFamily.major, '^7#11': ChordFamily.major,
      '13b9': ChordFamily.major, '7alt': ChordFamily.major, 'maj7': ChordFamily.major,
      'add9': ChordFamily.major, '69': ChordFamily.major,
      '-': ChordFamily.minor, '-7': ChordFamily.minor, 'm': ChordFamily.minor,
      'm7': ChordFamily.minor, '-^7': ChordFamily.minor, '-b6': ChordFamily.minor,
      'h7': ChordFamily.diminished, 'o7': ChordFamily.diminished,
      '-7b5': ChordFamily.diminished, 'dim': ChordFamily.diminished,
      '+': ChordFamily.augmented, '7#5': ChordFamily.augmented,
      'sus': ChordFamily.suspended, '7sus': ChordFamily.suspended,
      '9sus': ChordFamily.suspended, '2': ChordFamily.suspended,
    };
    for (final e in cases.entries) {
      test('« ${e.key} » → ${e.value.name}', () {
        expect(familyOf(e.key), e.value);
      });
    }

    test('N.C. et symboles illisibles : rien à attendre', () {
      expect(ChordExpectation.of(ChordParser.parse('n')), isNull);
      expect(ChordExpectation.of(ChordParser.parse('x')), isNull);
    });
  });

  test('étapes : doublons fusionnés, N.C. sautés, positions conservées', () {
    final steps = practiceSteps(chart([
      [['C'], ['C'], ['G', 'G7'], ['n']],
      [['A-'], ['F']],
    ]));
    expect([for (final s in steps) s.chord.raw], ['C', 'G', 'G7', 'A-', 'F']);
    expect(steps.first.refs, [
      (section: 0, bar: 0, chord: 0),
      (section: 0, bar: 1, chord: 0),
    ]);
    expect(steps[2].refs, [(section: 0, bar: 2, chord: 1)]);
    expect(steps[3].refs, [(section: 1, bar: 0, chord: 0)]);
  });

  test('on enchaîne C G Am F : chaque accord validé après avoir été joué', () {
    final session = PracticeSession(practiceSteps(chart([
      [['C'], ['G'], ['A-'], ['F']],
    ])));
    final shapes = ['x32010', '320003', 'x02210', '133211'];
    final validations = play(session, concat([
      for (var i = 0; i < shapes.length; i++)
        guitarStrum(shapes[i], seconds: 1.2, seed: i),
    ]));
    expect(session.finished, isTrue);
    expect(validations, hasLength(4));
    for (var i = 0; i < 4; i++) {
      expect(validations[i], inInclusiveRange(i * 1.2, i * 1.2 + 0.8),
          reason: 'accord ${i + 1}');
    }
  });

  test('une note de Sol seule ne valide ni Gsus4 ni G', () {
    for (final expected in ['Gsus', 'G']) {
      final session = PracticeSession(practiceSteps(chart([
        [[expected]],
      ])));
      play(session, guitarStrum('xxx0xx', seconds: 1.5));
      play(session, guitarStrum('3xxxxx', seconds: 1.5, seed: 2));
      expect(session.index, 0, reason: expected);
    }
  });

  test('un Sol joué pendant que le Do résonne ne valide pas G', () {
    final session = PracticeSession(practiceSteps(chart([
      [['C'], ['G']],
    ])));
    final c = guitarStrum('x32010', seconds: 2.5);
    final g = guitarStrum('3xxxxx', seconds: 1.3, seed: 2);
    // Le Sol grave arrive à 1,2 s, le Do continue de sonner par-dessus.
    final mix = Float64List.fromList(c);
    final at = (1.2 * 44100).round();
    for (var i = 0; i < g.length && at + i < mix.length; i++) {
      mix[at + i] += g[i];
    }
    play(session, mix);
    expect(session.index, 1, reason: 'C validé, G pas encore');
  });

  test('un mauvais accord ne valide rien', () {
    final session = PracticeSession(practiceSteps(chart([
      [['G'], ['C']],
    ])));
    play(session, concat([
      guitarStrum('x32010', seconds: 1.2),
      guitarStrum('x02210', seconds: 1.2, seed: 2),
    ]));
    expect(session.index, 0);
  });

  test('grille en jazz : l\'extension notée ne gêne pas (C^7#11 joué Cmaj7)', () {
    final session = PracticeSession(practiceSteps(chart([
      [['C^7#11'], ['A-9'], ['D7b9']],
    ])));
    play(session, concat([
      guitarStrum('x32000', seconds: 1.2),
      guitarStrum('x02010', seconds: 1.2, seed: 2),
      guitarStrum('xx0212', seconds: 1.2, seed: 3),
    ]));
    expect(session.finished, isTrue);
  });

  test('C puis C7 : l\'accord qui résonne ne valide pas le suivant', () {
    final session = PracticeSession(practiceSteps(chart([
      [['C'], ['C7']],
    ])));
    play(session, guitarStrum('x32010', seconds: 2.5));
    expect(session.index, 1, reason: 'C validé, C7 attend un nouveau coup');

    play(session, guitarStrum('x32310', seconds: 1.2, seed: 4));
    expect(session.finished, isTrue);
  });

  test('saut dans la grille et retour au début', () {
    final session = PracticeSession(practiceSteps(chart([
      [['C'], ['C', 'G'], ['F']],
    ])));
    expect(session.stepOf((section: 0, bar: 1, chord: 0)), 0);
    expect(session.stepOf((section: 0, bar: 2, chord: 0)), 2);
    session.jumpTo(2);
    expect(session.current?.chord.raw, 'F');
    session.restart();
    expect(session.index, 0);
  });
}
