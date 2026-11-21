import 'dart:math' as math;
import 'dart:typed_data';

/// Signaux de test : accords synthétiques (piano additif, guitare
/// Karplus-Strong), bruit. Déterministes (graine fixe).

double midiToHz(num midi, {double a4 = 440}) => a4 * math.pow(2, (midi - 69) / 12);

/// Notes tenues, harmoniques décroissants, légère inharmonicité (type piano).
Float64List pianoChord(
  List<int> midis, {
  double sampleRate = 11025,
  double seconds = 1.2,
  double a4 = 440,
  double amplitude = 0.3,
  int seed = 1,
}) {
  final rnd = math.Random(seed);
  final n = (sampleRate * seconds).round();
  final out = Float64List(n);
  for (final m in midis) {
    final f0 = midiToHz(m, a4: a4);
    for (var h = 1; h <= 10; h++) {
      final f = h * f0 * math.sqrt(1 + 2e-4 * h * h);
      if (f >= sampleRate / 2) break;
      final amp = amplitude / midis.length * math.pow(0.55, h - 1);
      final phase = rnd.nextDouble() * 2 * math.pi;
      final w = 2 * math.pi * f / sampleRate;
      for (var i = 0; i < n; i++) {
        out[i] += amp * math.exp(-i / (sampleRate * 1.5)) * math.sin(w * i + phase);
      }
    }
  }
  return out;
}

/// Accordage standard, cordes à vide (E2 A2 D3 G3 B3 E4).
const _openStrings = [40, 45, 50, 55, 59, 64];

/// Notes MIDI d'une position de guitare notée « x32010 » (x = corde muette).
List<int> guitarShape(String frets) => [
      for (var s = 0; s < 6; s++)
        if (frets[s] != 'x') _openStrings[s] + int.parse(frets[s], radix: 16),
    ];

/// Accord gratté (cordes décalées de [strumDelay], 12 ms par défaut ; plus
/// long pour un arpège), synthèse Karplus-Strong.
/// Gain de boucle réglé pour que chaque corde résonne ~3 s, comme une vraie.
/// L'excitation est filtrée pour que les harmoniques décroissent en ~1/h comme
/// sur une corde pincée ; [bright] garde le bruit blanc d'origine (spectre
/// plat jusqu'au 10e harmonique : cas extrême).
Float64List guitarStrum(
  String frets, {
  double sampleRate = 44100,
  double seconds = 1.2,
  double a4 = 440,
  double amplitude = 0.3,
  int seed = 1,
  bool bright = false,
  double strumDelay = 0.012,
}) {
  final rnd = math.Random(seed);
  final n = (sampleRate * seconds).round();
  final out = Float64List(n);
  final notes = guitarShape(frets);
  for (var s = 0; s < notes.length; s++) {
    final start = (s * strumDelay * sampleRate).round();
    // Boucle = ligne (len) + moyenneur (0,5) + passe-tout fractionnaire (frac).
    final period = sampleRate / midiToHz(notes[s], a4: a4) - 0.5;
    var len = period.floor();
    var frac = period - len;
    if (frac < 0.1) {
      len -= 1;
      frac += 1;
    }
    final line = Float64List(len);
    final f0 = midiToHz(notes[s], a4: a4);
    // Passe-bas à 1 pôle vers 2·f0 : pente de −6 dB/octave au-delà.
    final alpha = bright ? 1.0 : 1 - math.exp(-2 * math.pi * 2 * f0 / sampleRate);
    var lp = 0.0;
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < len; i++) {
        final noise = pass == 0 ? rnd.nextDouble() * 2 - 1 : line[i];
        lp += alpha * (noise - lp);
        line[i] = lp;
      }
    }
    var peak = 0.0;
    for (final v in line) {
      peak = math.max(peak, v.abs());
    }
    for (var i = 0; i < len; i++) {
      line[i] /= peak;
    }
    final c = (1 - frac) / (1 + frac);
    final gain = math.min(0.9999,
        math.pow(0.001, 1 / (3 * f0)) / math.cos(math.pi * f0 / sampleRate));
    var idx = 0;
    var lastDelayed = 0.0, apIn = 0.0, apOut = 0.0;
    for (var i = start; i < n; i++) {
      final y = line[idx];
      out[i] += amplitude / notes.length * y;
      final avg = gain * 0.5 * (y + lastDelayed);
      lastDelayed = y;
      final ap = c * avg + apIn - c * apOut;
      apIn = avg;
      apOut = ap;
      line[idx] = ap;
      idx = (idx + 1) % len;
    }
  }
  return out;
}

Float64List whiteNoise({
  double sampleRate = 11025,
  double seconds = 1.2,
  double amplitude = 0.05,
  int seed = 7,
}) {
  final rnd = math.Random(seed);
  final n = (sampleRate * seconds).round();
  return Float64List.fromList(
      [for (var i = 0; i < n; i++) amplitude * (rnd.nextDouble() * 2 - 1)]);
}

Float64List concat(List<Float64List> parts) {
  final out = Float64List(parts.fold(0, (s, p) => s + p.length));
  var o = 0;
  for (final p in parts) {
    out.setAll(o, p);
    o += p.length;
  }
  return out;
}
