import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Ce que contient une fenêtre d'audio, résumé en classes de hauteur.
class ChromaFrame {
  /// Énergie de chacune des 12 classes de hauteur (C = 0), maximum ramené à 1.
  /// Tout à zéro si la fenêtre ne contient aucun partiel exploitable.
  final Float64List chroma;

  /// Classe de hauteur de la note la plus grave nettement présente.
  final int? bassPitchClass;

  /// Force relative (0..1) de cette basse.
  final double bassStrength;

  /// Écart moyen des partiels à la grille La 440 (vecteur sur le cercle des
  /// cents, pondéré par l'amplitude) : à cumuler d'une fenêtre à l'autre pour
  /// estimer l'accordage, cf. [TuningTracker].
  final double tuningX;
  final double tuningY;

  /// Présence estimée (0..1) de chaque note de la tessiture analysée, du plus
  /// grave au plus aigu.
  final Float64List? notes;

  const ChromaFrame({
    required this.chroma,
    this.notes,
    this.bassPitchClass,
    this.bassStrength = 0,
    this.tuningX = 0,
    this.tuningY = 0,
  });

  bool get isEmpty => chroma.every((v) => v == 0);
}

/// Spectre → notes présentes → chromagramme.
///
/// 1. Seuls les pics nets du spectre comptent (à la HPCP) : le bruit large
///    bande et l'étalement d'une note sur ses voisines sont écartés.
/// 2. Les pics sont expliqués par des notes et leurs harmoniques (moindres
///    carrés non négatifs, comme le chroma NNLS de Chordino) : le 3e
///    harmonique d'un Si grave n'est plus compté comme un Fa♯ joué.
class ChromaAnalyzer {
  ChromaAnalyzer({
    required this.sampleRate,
    required this.frameSize,
    this.minMidi = 36,
    this.maxMidi = 84,
    this.maxPartialMidi = 100,
    this.bassPartialDecay = 0.85,
    this.treblePartialDecay = 0.6,
    this.nnlsIterations = 40,
    this.compression = 10,
    this.bassThreshold = 0.28,
  })  : assert(frameSize & (frameSize - 1) == 0, 'puissance de 2 attendue'),
        _fft = FFT(frameSize),
        _window = _hann(frameSize),
        _buffer = Float64List(frameSize),
        _magnitudes = Float64List(frameSize ~/ 2 + 1),
        _salience = Float64List(maxPartialMidi - minMidi + 1) {
    _buildNoteModel();
  }

  final double sampleRate;
  final int frameSize;

  /// Notes cherchées, en MIDI (36 = C2, 84 = C6).
  final int minMidi;
  final int maxMidi;

  /// Les partiels sont relevés plus haut que les notes cherchées : ceux
  /// d'au-dessus de C6 sont des harmoniques à attribuer aux notes plus graves,
  /// pas des notes fantômes.
  final int maxPartialMidi;

  /// Amplitude d'un harmonique relativement au précédent, dans le modèle de
  /// note : pour la note la plus grave de la tessiture et pour la plus aiguë
  /// (interpolation entre les deux). Les cordes graves sont plus riches en
  /// harmoniques, et le micro d'un téléphone atténue leur fondamentale.
  final double bassPartialDecay;
  final double treblePartialDecay;

  final int nnlsIterations;

  /// Compression log de la présence des notes, pour qu'une basse puissante
  /// n'écrase pas les notes aiguës de l'accord.
  final double compression;

  /// Présence minimale (0..1) de la note la plus grave pour la tenir pour la
  /// basse. Bas, car le micro d'un téléphone restitue mal les fondamentales
  /// graves.
  final double bassThreshold;

  final FFT _fft;
  final Float64List _window;
  final Float64List _buffer;
  final Float64List _magnitudes;
  final Float64List _salience;
  final _neighbourhood = Float64List(2 * _floorReach + 1);

  /// Un pic doit dépasser ce multiple du bruit de fond local (médiane des
  /// amplitudes alentour : un pic voisin plus fort ne le masque pas)…
  static const _peakToFloor = 3.0;
  static const _floorReach = 24;

  /// … et ne pas être à plus de 40 dB sous le pic le plus fort.
  static const _peakFloor = 0.01;

  /// Note la plus haute (MIDI) considérée comme candidate pour la basse.
  static const _bassMaxMidi = 64;

  /// Écarts (demi-tons) des harmoniques 1 à 16 qui tombent sur une note (le
  /// 7e, le 11e, le 13e et le 14e sont trop loin du tempérament égal).
  static const _partials = [
    (1, 0), (2, 12), (3, 19), (4, 24), (5, 28), (6, 31), (8, 36), //
    (9, 38), (10, 40), (12, 43), (15, 47), (16, 48),
  ];

  /// Gram du dictionnaire de notes (n × n) et, pour chaque note, ses
  /// harmoniques dans la tessiture : (indice, amplitude).
  late final Float64List _gram;
  late final List<List<(int, double)>> _noteModel;

  int get _size => maxMidi - minMidi + 1;

  void _buildNoteModel() {
    final n = _size;
    final bins = _salience.length;
    _noteModel = [
      for (var j = 0; j < n; j++)
        [
          for (final (h, offset) in _partials)
            if (j + offset < bins)
              (
                j + offset,
                math
                    .pow(
                      bassPartialDecay +
                          (treblePartialDecay - bassPartialDecay) * j / (n - 1),
                      h - 1,
                    )
                    .toDouble(),
              ),
        ],
    ];
    _gram = Float64List(n * n);
    for (var a = 0; a < n; a++) {
      for (var b = 0; b < n; b++) {
        var g = 0.0;
        for (final (i, wa) in _noteModel[a]) {
          for (final (k, wb) in _noteModel[b]) {
            if (i == k) g += wa * wb;
          }
        }
        _gram[a * n + b] = g;
      }
    }
  }

  /// [frame] doit contenir exactement [frameSize] échantillons.
  /// [tuningCents] décale la grille des demi-tons (accordage estimé).
  ChromaFrame analyze(List<double> frame, {double tuningCents = 0}) {
    final n = frameSize;
    var mean = 0.0;
    for (var i = 0; i < n; i++) {
      mean += frame[i];
    }
    mean /= n;
    for (var i = 0; i < n; i++) {
      _buffer[i] = (frame[i] - mean) * _window[i];
    }

    final spectrum = _fft.realFft(_buffer);
    final half = n ~/ 2;
    for (var k = 0; k <= half; k++) {
      final c = spectrum[k];
      _magnitudes[k] = math.sqrt(c.x * c.x + c.y * c.y);
    }

    final binHz = sampleRate / n;
    final kMin = math.max(2, (_midiToHz(minMidi - 0.5) / binHz).floor());
    final kMax =
        math.min(half - 2, (_midiToHz(maxPartialMidi + 0.5) / binHz).ceil());
    var maxMag = 0.0;
    for (var k = kMin; k <= kMax; k++) {
      if (_magnitudes[k] > maxMag) maxMag = _magnitudes[k];
    }
    final empty = ChromaFrame(chroma: Float64List(12));
    if (maxMag < 1e-9) return empty;

    _salience.fillRange(0, _salience.length, 0);
    var tx = 0.0, ty = 0.0, tw = 0.0;
    final floor = maxMag * _peakFloor;

    for (var k = kMin; k <= kMax; k++) {
      final b = _magnitudes[k];
      if (b < floor || b <= _magnitudes[k - 1] || b < _magnitudes[k + 1]) {
        continue;
      }
      if (b < _peakToFloor * _localFloor(k, half)) continue;

      // Interpolation parabolique (log) : fréquence et amplitude du pic.
      final a = math.log(_magnitudes[k - 1] + 1e-12);
      final lb = math.log(b);
      final c = math.log(_magnitudes[k + 1] + 1e-12);
      final denom = a - 2 * lb + c;
      final p = denom == 0 ? 0.0 : 0.5 * (a - c) / denom;
      final freq = (k + p) * binHz;
      final amp = math.exp(lb - 0.25 * (a - c) * p);
      final midi = 69 + 12 * math.log(freq / 440) / math.ln2;

      final dev = midi - midi.roundToDouble();
      tx += amp * math.cos(2 * math.pi * dev);
      ty += amp * math.sin(2 * math.pi * dev);
      tw += amp;

      final tuned = midi - tuningCents / 100;
      final m = tuned.round();
      if (m < minMidi || m > maxPartialMidi) continue;
      // Un partiel entre deux demi-tons (harmonique 7, note fausse) compte peu.
      final w = math.cos(math.pi * (tuned - m));
      _salience[m - minMidi] += amp * w * w;
    }

    final notes = _explainByNotes(_salience);
    var maxNote = 0.0;
    for (final v in notes) {
      if (v > maxNote) maxNote = v;
    }
    if (maxNote <= 0) return empty;

    final norm = math.log(1 + compression);
    for (var i = 0; i < notes.length; i++) {
      notes[i] = math.log(1 + compression * notes[i] / maxNote) / norm;
    }

    final chroma = Float64List(12);
    for (var i = 0; i < notes.length; i++) {
      final midi = minMidi + i;
      chroma[midi % 12] += _registerWeight(midi) * notes[i];
    }
    var maxChroma = 0.0;
    for (final v in chroma) {
      if (v > maxChroma) maxChroma = v;
    }
    for (var i = 0; i < 12; i++) {
      chroma[i] /= maxChroma;
    }

    int? bass;
    var bassStrength = 0.0;
    final bassEnd = math.min(_bassMaxMidi, maxMidi) - minMidi;
    for (var i = 0; i <= bassEnd; i++) {
      final s = notes[i];
      final isPeak = (i == 0 || s >= notes[i - 1]) &&
          (i + 1 >= notes.length || s >= notes[i + 1]);
      if (s >= bassThreshold && isPeak) {
        bass = (minMidi + i) % 12;
        bassStrength = s;
        break;
      }
    }

    return ChromaFrame(
      chroma: chroma,
      notes: notes,
      bassPitchClass: bass,
      bassStrength: bassStrength,
      tuningX: tw > 0 ? tx / tw : 0,
      tuningY: tw > 0 ? ty / tw : 0,
    );
  }

  /// Médiane des amplitudes sur ±1/6 d'octave autour de la case [k]
  /// (entre ±4 et ±[_floorReach] cases).
  double _localFloor(int k, int half) {
    final reach = (k * 0.12).round().clamp(4, _floorReach);
    final lo = math.max(0, k - reach);
    final hi = math.min(half, k + reach);
    final count = hi - lo + 1;
    for (var i = 0; i < count; i++) {
      _neighbourhood[i] = _magnitudes[lo + i];
    }
    final view = Float64List.sublistView(_neighbourhood, 0, count)..sort();
    return view[count ~/ 2];
  }

  /// Présence de chaque note (≥ 0) telle que notes × harmoniques ≈ spectre,
  /// par mises à jour multiplicatives (Lee & Seung) : simple, toujours
  /// positif, et une quarantaine d'itérations suffisent sur 61 notes.
  Float64List _explainByNotes(Float64List observed) {
    final n = _size;
    final target = Float64List(n); // Dᵀ·observé
    for (var j = 0; j < n; j++) {
      var t = 0.0;
      for (final (i, w) in _noteModel[j]) {
        t += w * observed[i];
      }
      target[j] = t;
    }
    final x = Float64List.sublistView(Float64List.fromList(observed), 0, n);
    final gx = Float64List(n);
    for (var it = 0; it < nnlsIterations; it++) {
      for (var a = 0; a < n; a++) {
        var g = 0.0;
        final row = a * n;
        for (var b = 0; b < n; b++) {
          g += _gram[row + b] * x[b];
        }
        gx[a] = g;
      }
      for (var a = 0; a < n; a++) {
        x[a] = gx[a] > 1e-12 ? x[a] * target[a] / gx[a] : 0;
      }
    }
    return x;
  }

  /// Au-dessus de B4, on entend surtout des harmoniques : poids décroissant.
  static double _registerWeight(int midi) {
    if (midi <= 71) return 1;
    return math.max(0.4, 1 - (midi - 71) / 24);
  }

  static double _midiToHz(num midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

  static Float64List _hann(int n) {
    final w = Float64List(n);
    for (var i = 0; i < n; i++) {
      w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    }
    return w;
  }
}

/// Estime l'accordage réel (écart au La 440, en cents) en cumulant les écarts
/// des partiels de fenêtre en fenêtre. Moyenne circulaire : +49 et −49 cents
/// sont voisins.
class TuningTracker {
  TuningTracker({this.smoothing = 0.05});

  /// Poids d'une nouvelle fenêtre dans la moyenne glissante.
  final double smoothing;

  double _x = 0, _y = 0;

  /// Accordage courant, ou 0 tant que l'estimation n'est pas assez cohérente.
  double get cents {
    if (math.sqrt(_x * _x + _y * _y) < 0.25) return 0;
    return math.atan2(_y, _x) / (2 * math.pi) * 100;
  }

  void add(ChromaFrame frame) {
    _x += smoothing * (frame.tuningX - _x);
    _y += smoothing * (frame.tuningY - _y);
  }

  void reset() => _x = _y = 0;
}
