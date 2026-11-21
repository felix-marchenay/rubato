import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/audio/pcm.dart';

void main() {
  group('Pcm16Decoder', () {
    test('little-endian signé, échantillon coupé entre deux morceaux', () {
      final d = Pcm16Decoder();
      final a = d.convert(Uint8List.fromList([0x00, 0x80, 0xff]));
      final b = d.convert(Uint8List.fromList([0x7f, 0x01]));
      final c = d.convert(Uint8List.fromList([0x00]));
      expect(a, [-1.0]);
      expect(b, [closeTo(32767 / 32768, 1e-9)]);
      expect(c, [closeTo(1 / 32768, 1e-9)]);
    });
  });

  group('Decimator', () {
    double amplitudeAfter(double freq) {
      final input = [
        for (var i = 0; i < 44100; i++) math.sin(2 * math.pi * freq * i / 44100),
      ];
      final out = Decimator(4).process(input);
      return out.skip(200).map((v) => v.abs()).reduce(math.max);
    }

    test('laisse passer le registre utile', () {
      expect(amplitudeAfter(1000), closeTo(1, 0.02));
    });

    test('coupe ce qui se replierait sous la nouvelle fréquence de Nyquist', () {
      expect(amplitudeAfter(8000), lessThan(0.01));
    });

    test('morceaux successifs = traitement d\'un bloc', () {
      final input = [for (var i = 0; i < 1000; i++) math.sin(i * 0.37)];
      final whole = Decimator(4).process(input);
      final d = Decimator(4);
      final parts = [...d.process(input.sublist(0, 333)), ...d.process(input.sublist(333))];
      expect(parts.length, whole.length);
      for (var i = 0; i < whole.length; i++) {
        expect(parts[i], closeTo(whole[i], 1e-12));
      }
    });
  });
}
