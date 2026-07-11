import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/codec/chord_parser.dart';
import 'package:mscore/src/codec/json_chord_chart_codec.dart';

void main() {
  group('ChordParser', () {
    test('accord simple avec qualité', () {
      final c = ChordParser.parse('Bb^7');
      expect(c.rootName, 'Bb');
      expect(c.quality, '^7');
      expect(c.bassName, isNull);
    });

    test('accord slash', () {
      final c = ChordParser.parse('C/E');
      expect(c.rootName, 'C');
      expect(c.bassName, 'E');
    });

    test('N.C.', () {
      expect(ChordParser.parse('n').isNoChord, isTrue);
    });

    test('classe de hauteur (Db == C#)', () {
      expect(ChordParser.parse('Db').root!.value, 1);
      expect(ChordParser.parse('C#').root!.value, 1);
    });
  });

  group('JsonChordChartCodec', () {
    const codec = JsonChordChartCodec();
    const src =
        '{"key":"Gm","time":"4/4","sections":[{"label":"A","bars":[{"chords":["C-7","F7"]}]}]}';

    test('décodage', () {
      final chart = codec.decode(src);
      expect(chart.key!.name, 'Gm');
      expect(chart.time.toString(), '4/4');
      expect(chart.sections.single.bars.single.chords.length, 2);
    });

    test('aller-retour encode/decode', () {
      final chart = codec.decode(src);
      final again = codec.decode(codec.encode(chart));
      expect(again.sections.single.bars.single.chords.first.raw, 'C-7');
    });
  });
}
