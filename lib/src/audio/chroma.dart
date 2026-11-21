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

  /// Nombre de classes de hauteur distinctes nettement présentes : moins de
  /// trois, ce n'est pas un accord (une note seule, une quinte).
  final int noteCount;

  const ChromaFrame({
    required this.chroma,
    this.notes,
    this.noteCount = 0,
    this.bassPitchClass,
    this.bassStrength = 0,
    this.tuningX = 0,
    this.tuningY = 0,
  });

  bool get isEmpty => chroma.every((v) => v == 0);
}

/// Notes estimées dans une fenêtre : présence linéaire (non normalisée, donc
/// comparable d'une fenêtre à l'autre) de chaque note de la tessiture.
class NoteEstimate {
  final Float64List levels;

  /// Énergie relevée à la fondamentale même de chaque note, avant de la
  /// répartir entre notes et harmoniques : les harmoniques d'une autre note ne
  /// la font pas bouger, d'où son emploi pour repérer les attaques.
  final Float64List fundamentals;
  final double tuningX;
  final double tuningY;

  NoteEstimate(
    this.levels, {
    Float64List? fundamentals,
    this.tuningX = 0,
    this.tuningY = 0,
  }) : fundamentals = fundamentals ?? Float64List(levels.length);
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
    this.noteFloor = 0.06,
    this.bassThreshold = 0.28,
    this.windowPeak = 0.5,
  })  : assert(frameSize & (frameSize - 1) == 0, 'puissance de 2 attendue'),
        _fft = FFT(frameSize),
        _window = _hann(frameSize, windowPeak),
        _buffer = Float64List(frameSize),
        _magnitudes = Float64List(frameSize ~/ 2 + 1),
        _salience = Float64List(maxPartialMidi - minMidi + 1) {
    _buildNoteModel();
  }

  final double sampleRate;
  final int frameSize;

  /// Position du sommet de la fenêtre d'analyse (0,5 = Hann symétrique).
  /// Plus tard, le son récent pèse davantage : le détecteur réagit plus vite
  /// au prix d'un peu de fuite spectrale.
  final double windowPeak;

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

  /// Une note plus faible que cette fraction de la plus forte est ignorée :
  /// résidus d'harmoniques, cordes qui vibrent par sympathie.
  final double noteFloor;

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

  /// Nombre de notes suivies (taille de [NoteEstimate.levels]).
  int get noteSlots => _size;

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
  ChromaFrame analyze(List<double> frame, {double tuningCents = 0}) =>
      summarize(estimateNotes(frame, tuningCents: tuningCents));

  /// Première moitié de [analyze] : quelles notes sonnent, et à quel niveau.
  NoteEstimate estimateNotes(List<double> frame, {double tuningCents = 0}) {
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
    if (maxMag < 1e-9) return NoteEstimate(Float64List(_size));

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

    return NoteEstimate(
      _explainByNotes(_salience),
      fundamentals: Float64List.fromList(
          Float64List.sublistView(_salience, 0, _size)),
      tuningX: tw > 0 ? tx / tw : 0,
      tuningY: tw > 0 ? ty / tw : 0,
    );
  }

  /// Seconde moitié de [analyze] : notes → chroma, basse, nombre de notes.
  ChromaFrame summarize(NoteEstimate estimate) {
    final notes = Float64List.fromList(estimate.levels);
    var maxNote = 0.0;
    for (final v in notes) {
      if (v > maxNote) maxNote = v;
    }
    if (maxNote <= 0) return ChromaFrame(chroma: Float64List(12));

    final norm = math.log(1 + compression);
    var classes = 0;
    for (var i = 0; i < notes.length; i++) {
      final x = notes[i] / maxNote;
      if (x >= noteFloor && !_looksLikeHarmonic(estimate.levels, i)) {
        classes |= 1 << ((minMidi + i) % 12);
      }
      notes[i] = x < noteFloor ? 0 : math.log(1 + compression * x) / norm;
    }
    var noteCount = 0;
    for (; classes != 0; classes &= classes - 1) {
      noteCount++;
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
      noteCount: noteCount,
      bassPitchClass: bass,
      bassStrength: bassStrength,
      tuningX: estimate.tuningX,
      tuningY: estimate.tuningY,
    );
  }

  /// Harmoniques 5 (tierce majeure deux octaves au-dessus), 7 (septième
  /// mineure) et 9 (seconde) : leur résidu reste faible, alors qu'une vraie
  /// note à cette place pèse nettement plus. (La quinte, harmonique 3, ne se
  /// laisse pas trancher ainsi : résidu et vraie note s'y chevauchent.)
  static const _ghosts = [(28, 0.3), (34, 0.3), (38, 0.3)];

  /// La note [i] pourrait n'être qu'un harmonique d'une note plus grave
  /// nettement plus forte : un Sol seul laisse un peu de Si, et Sol-Ré-Si
  /// formerait un accord. On ne la compte pas pour décider si c'est un accord.
  static bool _looksLikeHarmonic(Float64List levels, int i) {
    for (final (offset, ratio) in _ghosts) {
      final j = i - offset;
      if (j >= 0 && levels[i] <= ratio * levels[j]) return true;
    }
    return false;
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

  /// Fenêtre de Hann, éventuellement asymétrique : son sommet placé à
  /// [peak] (0,5 = symétrique) ; plus tard, le son récent pèse davantage.
  static Float64List _hann(int n, double peak) {
    final w = Float64List(n);
    final top = (peak * (n - 1)).round();
    for (var i = 0; i < n; i++) {
      final x = i <= top ? i / top : 1 + (i - top) / (n - 1 - top);
      w[i] = 0.5 - 0.5 * math.cos(math.pi * x);
    }
    return w;
  }
}

/// Rémanence : une note pèse de moins en moins à mesure que le temps passe
/// depuis qu'elle a été jouée. Les notes d'un accord précédent qui résonnent
/// encore s'effacent ainsi devant celles qu'on vient de jouer. Une rémanence
/// courte ne retient que les notes fraîches ; une longue laisse le temps
/// d'égrener un accord en arpège.
class NoteRemanence {
  NoteRemanence(int notes, {required this.hopSeconds, this.seconds = 1.2})
      : _trough = Float64List(notes),
        _age = Float64List(notes);

  /// Durée d'une trame d'analyse.
  final double hopSeconds;

  /// Constante de temps (s) : après ce délai sans nouvelle attaque, une note
  /// ne pèse plus que 37 % ; après le double, 14 %.
  double seconds;

  /// Remontée (× niveau le plus bas depuis la dernière attaque) de la
  /// fondamentale qui signale une nouvelle attaque de la note.
  static const _attackRise = 1.25;

  final Float64List _trough;
  final Float64List _age;

  /// Pondère les notes de [estimate] en place.
  void apply(NoteEstimate estimate) {
    final levels = estimate.levels;
    var loudest = 0.0;
    for (final l in levels) {
      if (l > loudest) loudest = l;
    }
    for (var j = 0; j < levels.length; j++) {
      final f = estimate.fundamentals[j];
      if (f > _attackRise * _trough[j] && levels[j] > 0.05 * loudest) {
        _age[j] = 0;
        _trough[j] = f;
      } else {
        _age[j] += hopSeconds;
        if (f < _trough[j]) _trough[j] = f;
      }
      levels[j] *= math.exp(-_age[j] / seconds);
    }
  }

  void reset() {
    _trough.fillRange(0, _trough.length, 0);
    _age.fillRange(0, _age.length, 0);
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
