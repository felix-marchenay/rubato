import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/audio/chord_detector.dart';
import 'package:mscore/src/audio/chord_vocabulary.dart';

import 'synth.dart';

/// Fait passer [signal] dans un détecteur neuf, par morceaux de taille
/// variable (comme le flux micro), et renvoie toutes les trames produites.
List<ListeningFrame> run(
  Float64List signal, {
  double sampleRate = 44100,
  ChordVocabulary vocabulary = ChordVocabulary.standard,
}) {
  final d = ChordDetector(sampleRate: sampleRate.round(), vocabulary: vocabulary);
  final frames = <ListeningFrame>[];
  var i = 0;
  var chunk = 1000;
  while (i < signal.length) {
    final end = (i + chunk).clamp(0, signal.length);
    frames.addAll(d.add(signal.sublist(i, end)));
    i = end;
    chunk = chunk == 1000 ? 3333 : 1000;
  }
  return frames;
}

String? finalChord(
  Float64List signal, {
  double sampleRate = 44100,
  ChordVocabulary vocabulary = ChordVocabulary.standard,
}) =>
    run(signal, sampleRate: sampleRate, vocabulary: vocabulary)
        .last
        .chord
        ?.toChord()
        .raw;

/// Accords successifs affichés (sans répétition).
List<String> shownChords(List<ListeningFrame> frames) {
  final out = <String>[];
  for (final f in frames) {
    final c = f.chord?.toChord().raw;
    if (c != null && (out.isEmpty || out.last != c)) out.add(c);
  }
  return out;
}

void main() {
  group('guitare, positions usuelles', () {
    const cases = {
      'x32010': 'C', '320003': 'G', 'xx0232': 'D', 'x02220': 'A', //
      '022100': 'E', '133211': 'F', 'x24442': 'B',
      'x02210': 'A-', '022000': 'E-', 'xx0231': 'D-', 'x24432': 'B-',
      '320001': 'G7', 'x02020': 'A7', '020100': 'E7', 'xx0212': 'D7',
      'x21202': 'B7', '131211': 'F7',
      'x02120': 'A^7', 'xx0222': 'D^7', '1x221x': 'F^7',
      'x02010': 'A-7', '022030': 'E-7', 'xx0211': 'D-7', 'x24232': 'B-7',
      'x02230': 'Asus', 'xx0233': 'Dsus', 'xx0230': 'Dsus2', 'x02200': 'Asus2',
      '032010': 'C/E', 'x20003': 'G/B', '2x0232': 'D/F#', '332010': 'C/G',
    };
    for (final e in cases.entries) {
      test('${e.key} → ${e.value}', () {
        expect(finalChord(guitarStrum(e.key)), e.value);
      });
    }
  });

  test('précision trame par trame sur un corpus de grattages', () {
    // Limite connue : une 7e portée par une seule corde (Cmaj7 x32000, Em7
    // 022030) est parfois lue comme la triade, selon le grattage.
    const shapes = {
      'x32010': 'C', '320003': 'G', 'xx0232': 'D', 'x02220': 'A', //
      '022000': 'E-', 'x02210': 'A-', '320001': 'G7', 'x02020': 'A7',
      'x32000': 'C^7', 'x02010': 'A-7', '022030': 'E-7', '032010': 'C/E',
    };
    var ok = 0, total = 0;
    for (final e in shapes.entries) {
      for (final seed in [1, 2, 3]) {
        final frames = run(guitarStrum(e.key, seed: seed, seconds: 1.5));
        // On juge une fois la première demi-seconde passée.
        for (final f in frames.skip(frames.length ~/ 3)) {
          total++;
          if (f.chord?.toChord().raw == e.value) ok++;
        }
      }
    }
    expect(ok / total, greaterThan(0.92));
  });

  group('piano, 12 fondamentales', () {
    for (final q in ChordVocabulary.standard.qualities) {
      test('qualité « ${q.symbol} », voicings serré et écarté', () {
        for (var root = 0; root < 12; root++) {
          final want = '${pitchClassNames[root]}${q.symbol}';
          final close = [for (final i in q.intervals) 48 + root + i];
          final spread = [
            36 + root,
            for (final i in q.intervals) 55 + (root + i - 7) % 12,
          ];
          expect(finalChord(pianoChord(close, sampleRate: 44100, seed: root)),
              want, reason: 'serré $close');
          expect(finalChord(pianoChord(spread, sampleRate: 44100, seed: root)),
              want, reason: 'écarté $spread');
        }
      });
    }
  });

  group('vocabulaire jazz : la basse départage les accords homonymes', () {
    const cases = {
      'C6': [36, 52, 55, 57],
      'A-7': [45, 48, 52, 55],
      'Bh7': [47, 57, 62, 65],
      'D-6': [38, 53, 57, 59],
      'G7sus': [43, 53, 60, 62],
      'C+': [48, 52, 56],
    };
    for (final e in cases.entries) {
      test('${e.value} → ${e.key}', () {
        expect(
          finalChord(pianoChord(e.value, sampleRate: 44100),
              vocabulary: ChordVocabulary.jazz),
          e.key,
        );
      });
    }
  });

  test('vocabulaire simple : une 7e est ramenée à sa triade', () {
    expect(
      finalChord(guitarStrum('320001'), vocabulary: ChordVocabulary.simple),
      'G',
    );
  });

  group('une note seule n\'est pas un accord : on affiche la note', () {
    // (position, note MIDI attendue) : la note jouée, à la bonne octave.
    const cases = {
      'xxx0xx': ('Sol3 à vide', 55),
      '3xxxxx': ('Sol2, riche en harmoniques', 43),
      'xxxxx3': ('Sol4', 67),
      'x0x2xx': ('octave La : la plus grave', 45),
    };
    for (final e in cases.entries) {
      test(e.value.$1, () {
        final frames = run(guitarStrum(e.key, seconds: 1.5));
        expect(frames.where((f) => f.chord != null), isEmpty);
        expect(frames.every((f) => f.candidates.isEmpty), isTrue);
        expect(frames.last.note, e.value.$2);
      });
    }

    test('un accord remplace la note affichée, et inversement', () {
      final d = ChordDetector(sampleRate: 44100);
      final afterNote = d.add(guitarStrum('xxx0xx', seconds: 1.2)).last;
      expect(afterNote.note, 55);
      expect(afterNote.chord, isNull);
      final afterChord = d.add(guitarStrum('x32010', seconds: 1.2, seed: 2)).last;
      expect(afterChord.chord?.toChord().raw, 'C');
      expect(afterChord.note, isNull);
      final afterLow = d.add(guitarStrum('3xxxxx', seconds: 1.2, seed: 3)).last;
      expect(afterLow.note, 43);
      expect(afterLow.chord, isNull);
    });

    test('un accord gratté n\'est jamais pris pour une note', () {
      final frames = run(guitarStrum('320003', seconds: 1.5));
      expect(frames.where((f) => f.note != null), isEmpty);
    });
  });

  group('rémanence', () {
    // Do égrené lentement, corde par corde, une note toutes les 0,6 s.
    final arpeggio = guitarStrum('x32010', strumDelay: 0.6, seconds: 3.5);

    List<ListeningFrame> runWith(double remanence) {
      final d = ChordDetector(sampleRate: 44100, remanenceSeconds: remanence);
      final frames = <ListeningFrame>[];
      for (var i = 0; i < arpeggio.length; i += 2048) {
        frames.addAll(d.add(arpeggio.sublist(
            i, (i + 2048).clamp(0, arpeggio.length))));
      }
      return frames;
    }

    test('longue : l\'arpège est reconnu comme un accord', () {
      final chord = runWith(4).last.chord;
      // La basse, jouée en premier, s'est beaucoup éteinte : on ne juge que
      // l'accord, pas son renversement.
      expect(chord?.root, 0);
      expect(chord?.quality, '');
    });

    test('courte : seules les notes fraîches comptent, pas d\'accord', () {
      expect(runWith(0.15).where((f) => f.chord != null), isEmpty);
    });
  });

  test('silence : aucun signal, aucun accord', () {
    final frames = run(Float64List(44100));
    expect(frames, isNotEmpty);
    expect(frames.every((f) => !f.hasSignal && f.chord == null), isTrue);
  });

  test('bruit blanc : jamais d\'accord', () {
    final frames = run(whiteNoise(sampleRate: 44100, seconds: 2));
    expect(frames.every((f) => f.hasSignal), isTrue);
    expect(frames.where((f) => f.chord != null), isEmpty);
  });

  test("l'accord reste affiché pendant un silence", () {
    final frames = run(concat([guitarStrum('x32010'), Float64List(44100)]));
    expect(frames.last.hasSignal, isFalse);
    expect(frames.last.chord?.toChord().raw, 'C');
  });

  test('changement d\'accord : pas de clignotement, réaction < 0,3 s', () {
    final c = guitarStrum('x32010', seconds: 1.5);
    final g = guitarStrum('320003', seconds: 1.5, seed: 2);
    final frames = run(concat([c, g]));
    expect(shownChords(frames), ['C', 'G']);

    // Une trame couvre un pas d'analyse ; on retrouve l'instant de bascule.
    final hop = (c.length + g.length) / frames.length;
    final switchAt = frames.indexWhere((f) => f.chord?.toChord().raw == 'G');
    final latency = (switchAt + 1) * hop / 44100 - 1.5;
    expect(latency, lessThan(0.3));
  });

  group('accordage décalé', () {
    for (final a4 in [446.0, 430.0]) {
      test('La = $a4 Hz', () {
        final frames = run(concat([
          guitarStrum('x32010', a4: a4, seconds: 1.5),
          guitarStrum('320003', a4: a4, seconds: 1.5, seed: 2),
        ]));
        expect(shownChords(frames), ['C', 'G']);
        final expected = 1200 * math.log(a4 / 440) / math.ln2;
        expect(frames.last.tuningCents, closeTo(expected, 6));
      });
    }
  });

  test('fréquences d\'entrée usuelles (48 kHz web, 16 kHz)', () {
    for (final rate in [48000.0, 16000.0]) {
      final sig = guitarStrum('x02210', sampleRate: rate);
      expect(finalChord(sig, sampleRate: rate), 'A-', reason: '$rate Hz');
    }
  });
}
