import 'dart:math' as math;
import 'dart:typed_data';

import 'chord_matcher.dart';
import 'chord_vocabulary.dart';
import 'chroma.dart';
import 'pcm.dart';

/// État de l'écoute après une fenêtre d'analyse.
class ListeningFrame {
  /// Chroma lissé (12 valeurs 0..1) : ce que « voit » le détecteur.
  final Float64List chroma;

  /// Niveau du signal sur le dernier pas d'analyse, en dBFS.
  final double levelDb;

  /// Le niveau dépasse le seuil : on analyse (sinon on garde l'accord affiché).
  final bool hasSignal;

  /// Accord stabilisé, celui à afficher. Reste en place pendant les silences.
  final ChordCandidate? chord;

  /// Tous les accords du vocabulaire classés pour cette seule fenêtre (vide
  /// pendant un silence) : pour juger un accord attendu (mode entraînement).
  final List<ChordCandidate> candidates;

  /// Accordage estimé (écart au La 440, en cents).
  final double tuningCents;

  const ListeningFrame({
    required this.chroma,
    required this.levelDb,
    required this.hasSignal,
    required this.chord,
    this.candidates = const [],
    required this.tuningCents,
  });
}

/// Évite le clignotement : un nouvel accord ne remplace l'accord affiché que
/// s'il gagne plusieurs fenêtres d'affilée, avec une marge suffisante.
class ChordStabilizer {
  ChordStabilizer({
    this.confirmFrames = 3,
    this.stickiness = 0.04,
    this.minScore = 0.55,
  });

  final int confirmFrames;

  /// Avance que doit prendre un challenger sur l'accord en place.
  final double stickiness;

  /// En dessous, la fenêtre est jugée non tonale (bruit, parole, percussions).
  final double minScore;

  ChordCandidate? current;
  ChordCandidate? _pending;
  int _count = 0;

  /// [ranked] : candidats de la fenêtre, triés ; null pendant un silence.
  ChordCandidate? update(List<ChordCandidate>? ranked) {
    final best = (ranked == null || ranked.isEmpty) ? null : ranked.first;
    if (best == null || best.score < minScore) {
      _pending = null;
      return current;
    }
    final cur = current;
    if (cur != null) {
      if (best.sameChordAs(cur)) {
        current = best;
        _pending = null;
        return current;
      }
      final curNow = ranked!.firstWhere(
        (c) => identical(c.template, cur.template),
        orElse: () => best,
      );
      if (!identical(curNow.template, best.template) &&
          best.score - curNow.score < stickiness) {
        _pending = null;
        return current;
      }
    }
    if (_pending != null && _pending!.sameChordAs(best)) {
      _count++;
    } else {
      _pending = best;
      _count = 1;
    }
    if (_count >= confirmFrames) {
      current = best;
      _pending = null;
    }
    return current;
  }

  void reset() {
    current = null;
    _pending = null;
    _count = 0;
  }
}

/// Chaîne complète : échantillons du micro → accord affiché.
///
/// Le signal est ramené vers ~11 kHz (seuls 60 Hz–2 kHz nous intéressent),
/// analysé toutes les ~45 ms sur une fenêtre de ~0,37 s (compromis entre la
/// finesse en fréquence nécessaire dans le grave et la réactivité).
class ChordDetector {
  ChordDetector({
    required int sampleRate,
    ChordVocabulary vocabulary = ChordVocabulary.standard,
    this.gateDb = -55,
    double remanenceSeconds = 1.2,
  })  : _decimator = Decimator(math.max(1, (sampleRate / 11025).round())),
        _vocabulary = vocabulary,
        _matcher = ChordMatcher(vocabulary) {
    analysisRate = sampleRate / _decimator.factor;
    frameSize = analysisRate > 12500 ? 8192 : 4096;
    hopSize = frameSize ~/ 8;
    _ring = Float64List(frameSize);
    _frame = Float64List(frameSize);
    _analyzer = ChromaAnalyzer(sampleRate: analysisRate, frameSize: frameSize);
    _remanence = NoteRemanence(
      _analyzer.noteSlots,
      hopSeconds: hopSize / analysisRate,
      seconds: remanenceSeconds,
    );
  }

  /// Moins de notes distinctes que ça, ce n'est pas un accord.
  static const minNotes = 3;

  final Decimator _decimator;
  late final double analysisRate;
  late final int frameSize;
  late final int hopSize;
  late final Float64List _ring;
  late final Float64List _frame;
  late final ChromaAnalyzer _analyzer;
  late final NoteRemanence _remanence;
  final _tuning = TuningTracker();
  final _stabilizer = ChordStabilizer();
  final _smoothed = Float64List(12);

  /// Seuil de niveau (dBFS) sous lequel on considère qu'il n'y a pas de son.
  double gateDb;

  ChordVocabulary _vocabulary;
  ChordMatcher _matcher;

  /// Durée (s) pendant laquelle une note jouée continue de compter, cf.
  /// [NoteRemanence].
  double get remanenceSeconds => _remanence.seconds;
  set remanenceSeconds(double s) => _remanence.seconds = s;

  ChordVocabulary get vocabulary => _vocabulary;
  set vocabulary(ChordVocabulary v) {
    if (v == _vocabulary) return;
    _vocabulary = v;
    _matcher = ChordMatcher(v);
    _stabilizer.reset();
  }

  int _writePos = 0;
  int _filled = 0;
  int _sinceHop = 0;
  double _hopEnergy = 0;

  /// Ajoute des échantillons (−1..1) ; renvoie une trame par pas d'analyse
  /// écoulé (souvent 0 ou 1, davantage si le morceau reçu est long).
  List<ListeningFrame> add(List<double> samples) {
    final frames = <ListeningFrame>[];
    for (final x in _decimator.process(samples)) {
      _ring[_writePos] = x;
      _writePos = (_writePos + 1) % frameSize;
      if (_filled < frameSize) _filled++;
      _hopEnergy += x * x;
      if (++_sinceHop < hopSize) continue;
      final rms = math.sqrt(_hopEnergy / hopSize);
      _sinceHop = 0;
      _hopEnergy = 0;
      if (_filled == frameSize) frames.add(_analyze(rms));
    }
    return frames;
  }

  ListeningFrame _analyze(double rms) {
    final levelDb = rms > 0 ? 20 * math.log(rms) / math.ln10 : -120.0;
    final hasSignal = levelDb >= gateDb;
    ChordCandidate? chord;
    var ranked = const <ChordCandidate>[];

    if (hasSignal) {
      for (var i = 0; i < frameSize; i++) {
        _frame[i] = _ring[(_writePos + i) % frameSize];
      }
      final notes = _analyzer.estimateNotes(_frame, tuningCents: _tuning.cents);
      _remanence.apply(notes.levels);
      final raw = _analyzer.summarize(notes);
      if (!raw.isEmpty) _tuning.add(raw);
      for (var i = 0; i < 12; i++) {
        _smoothed[i] = 0.5 * _smoothed[i] + 0.5 * raw.chroma[i];
      }
      // Une note seule (ou une quinte) n'est pas un accord, même si elle
      // ressemble à l'un d'eux plus qu'aux autres.
      ranked = raw.noteCount < minNotes
          ? const <ChordCandidate>[]
          : _matcher.rank(ChromaFrame(
              chroma: _smoothed,
              bassPitchClass: raw.bassPitchClass,
              bassStrength: raw.bassStrength,
            ));
      chord = _stabilizer.update(ranked);
    } else {
      for (var i = 0; i < 12; i++) {
        _smoothed[i] *= 0.8;
      }
      chord = _stabilizer.update(null);
    }

    return ListeningFrame(
      chroma: Float64List.fromList(_smoothed),
      levelDb: levelDb,
      hasSignal: hasSignal,
      chord: chord,
      candidates: ranked,
      tuningCents: _tuning.cents,
    );
  }

  void reset() {
    _writePos = 0;
    _filled = 0;
    _sinceHop = 0;
    _hopEnergy = 0;
    _ring.fillRange(0, frameSize, 0);
    _smoothed.fillRange(0, 12, 0);
    _tuning.reset();
    _remanence.reset();
    _stabilizer.reset();
  }
}
