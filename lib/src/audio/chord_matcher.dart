import '../domain/chord_chart.dart';
import 'chord_vocabulary.dart';
import 'chroma.dart';

/// Un accord candidat et son score pour une fenêtre donnée.
class ChordCandidate {
  final ChordTemplate template;

  /// Basse d'un renversement (C/E), null en position fondamentale.
  final int? bassPitchClass;

  /// Corrélation chroma/gabarit corrigée des bonus et pénalités (≈ −1..1).
  final double score;

  const ChordCandidate(this.template, this.bassPitchClass, this.score);

  int get root => template.root;
  String get quality => template.quality.symbol;

  /// Même accord, renversement compris.
  bool sameChordAs(ChordCandidate other) =>
      identical(template, other.template) &&
      bassPitchClass == other.bassPitchClass;

  Chord toChord() => Chord(
        rootName: pitchClassNames[root],
        quality: quality,
        bassName: bassPitchClass == null ? null : pitchClassNames[bassPitchClass!],
      );

  @override
  String toString() => '${toChord().raw} (${score.toStringAsFixed(2)})';
}

/// Compare un chroma à tous les gabarits du vocabulaire.
class ChordMatcher {
  ChordMatcher(ChordVocabulary vocabulary)
      : templates = buildChordTemplates(vocabulary);

  final List<ChordTemplate> templates;

  /// La note de basse est le meilleur indice de la fondamentale (C6 / Am7).
  static const rootBassBonus = 0.08;
  static const chordToneBassBonus = 0.02;
  static const foreignBassPenalty = 0.04;

  /// Force minimale de la basse pour annoncer un renversement.
  static const slashBassStrength = 0.35;

  /// Candidats triés du meilleur au moins bon ; vide si le chroma est plat.
  List<ChordCandidate> rank(ChromaFrame frame) {
    final z = standardize(frame.chroma);
    if (z == null) return const [];
    final bass = frame.bassPitchClass;
    final bassStrength = frame.bassStrength;

    final out = <ChordCandidate>[];
    for (final t in templates) {
      var score = 0.0;
      for (var i = 0; i < 12; i++) {
        score += z[i] * t.profile[i];
      }

      int? slash;
      if (bass != null) {
        if (bass == t.root) {
          score += rootBassBonus * bassStrength;
        } else if (t.contains(bass)) {
          score += chordToneBassBonus * bassStrength;
          if (bassStrength >= slashBassStrength) slash = bass;
        } else {
          score -= foreignBassPenalty * bassStrength;
        }
      }
      out.add(ChordCandidate(t, slash, score));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}
