import 'dart:math' as math;
import 'dart:typed_data';

/// Octets PCM 16 bits little-endian → échantillons flottants (−1..1).
/// Les morceaux du flux micro peuvent couper un échantillon en deux : l'octet
/// orphelin est gardé pour le morceau suivant.
class Pcm16Decoder {
  int? _pending;

  Float32List convert(Uint8List bytes) {
    var start = 0;
    final carry = _pending;
    final total = bytes.length + (carry == null ? 0 : 1);
    final out = Float32List(total ~/ 2);
    var o = 0;
    if (carry != null && bytes.isNotEmpty) {
      out[o++] = _sample(carry | (bytes[0] << 8));
      start = 1;
      _pending = null;
    }
    final end = start + (bytes.length - start) ~/ 2 * 2;
    for (var i = start; i < end; i += 2) {
      out[o++] = _sample(bytes[i] | (bytes[i + 1] << 8));
    }
    if (end < bytes.length) _pending = bytes[end];
    return out;
  }

  static double _sample(int u16) => (u16 >= 0x8000 ? u16 - 0x10000 : u16) / 32768;
}

/// Sous-échantillonnage d'un facteur entier, précédé d'un passe-bas (sinus
/// cardinal fenêtré de Blackman) contre le repliement spectral. Garde son état
/// d'un appel à l'autre : on peut lui passer le flux par morceaux.
class Decimator {
  Decimator(this.factor)
      : assert(factor >= 1),
        _taps = _design(factor),
        _history = Float64List(16 * factor + 1);

  final int factor;
  final Float64List _taps;
  final Float64List _history;
  int _pos = 0;
  int _phase = 0;

  List<double> process(List<double> input) {
    if (factor == 1) return input;
    final out = <double>[];
    final len = _history.length;
    for (final x in input) {
      _history[_pos] = x;
      _pos = (_pos + 1) % len;
      if (++_phase < factor) continue;
      _phase = 0;
      var y = 0.0;
      var j = _pos;
      for (var k = 0; k < len; k++) {
        j = j == 0 ? len - 1 : j - 1;
        y += _taps[k] * _history[j];
      }
      out.add(y);
    }
    return out;
  }

  static Float64List _design(int factor) {
    final len = 16 * factor + 1;
    final h = Float64List(len);
    if (factor == 1) {
      h[0] = 1;
      return h;
    }
    // Coupure un peu sous la nouvelle fréquence de Nyquist.
    final cutoff = 0.42 / factor;
    final mid = (len - 1) / 2;
    var sum = 0.0;
    for (var i = 0; i < len; i++) {
      final t = i - mid;
      final sinc = t == 0 ? 2 * cutoff : math.sin(2 * math.pi * cutoff * t) / (math.pi * t);
      final w = 0.42 -
          0.5 * math.cos(2 * math.pi * i / (len - 1)) +
          0.08 * math.cos(4 * math.pi * i / (len - 1));
      h[i] = sinc * w;
      sum += h[i];
    }
    for (var i = 0; i < len; i++) {
      h[i] /= sum;
    }
    return h;
  }
}
