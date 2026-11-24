import 'dart:math' as math;
import 'dart:typed_data';

/// Orthographe des 12 classes de hauteur (C = 0), celle des grilles usuelles.
const pitchClassNames = [
  'C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B', //
];

/// Qualité d'accord reconnaissable, au vocabulaire iReal Pro de `Chord.quality`.
class ChordQuality {
  final String symbol;

  /// Intervalles en demi-tons depuis la fondamentale.
  final List<int> intervals;

  const ChordQuality(this.symbol, this.intervals);
}

const _major = ChordQuality('', [0, 4, 7]);
const _minor = ChordQuality('-', [0, 3, 7]);
const _dom7 = ChordQuality('7', [0, 4, 7, 10]);
const _maj7 = ChordQuality('^7', [0, 4, 7, 11]);
const _min7 = ChordQuality('-7', [0, 3, 7, 10]);
const _sus4 = ChordQuality('sus', [0, 5, 7]);
const _sus2 = ChordQuality('sus2', [0, 2, 7]);
const _dim = ChordQuality('o', [0, 3, 6]);
const _aug = ChordQuality('+', [0, 4, 8]);
const _halfDim = ChordQuality('h7', [0, 3, 6, 10]);
const _dim7 = ChordQuality('o7', [0, 3, 6, 9]);
const _six = ChordQuality('6', [0, 4, 7, 9]);
const _minSix = ChordQuality('-6', [0, 3, 7, 9]);
const _sus7 = ChordQuality('7sus', [0, 5, 7, 10]);

/// Jeu de qualités cherchées. Plus il est riche, plus les confusions sont
/// fréquentes (C6 et Am7 ont les mêmes notes) : on laisse l'utilisateur choisir.
enum ChordVocabulary {
  simple('Simple', [_major, _minor]),
  standard('Standard', [_major, _minor, _dom7, _maj7, _min7, _sus4, _sus2, _dim]),
  jazz('Jazz', [
    _major, _minor, _dom7, _maj7, _min7, _sus4, _sus2, _dim, //
    _aug, _halfDim, _dim7, _six, _minSix, _sus7,
  ]);

  const ChordVocabulary(this.label, this.qualities);

  final String label;
  final List<ChordQuality> qualities;
}

/// Profil de chroma attendu pour un accord donné.
class ChordTemplate {
  final int root;
  final ChordQuality quality;

  /// Masque des classes de hauteur de l'accord (bit i = classe i).
  final int mask;

  /// Profil centré-réduit (moyenne nulle, norme 1) : le score d'un chroma
  /// centré-réduit est alors un simple produit scalaire (corrélation).
  final Float64List profile;

  ChordTemplate._(this.root, this.quality, this.mask, this.profile);

  int get size => quality.intervals.length;

  bool contains(int pitchClass) => mask & (1 << pitchClass) != 0;
}

/// Construit les gabarits des 12 fondamentales × qualités du vocabulaire.
///
/// Chaque note de l'accord contribue aussi un peu par ses harmoniques
/// (octave, quinte, tierce…) : même après séparation des notes, le chroma en
/// garde un résidu, que le gabarit anticipe au lieu de le compter comme une
/// note étrangère.
List<ChordTemplate> buildChordTemplates(
  ChordVocabulary vocabulary, {
  double harmonicDecay = 0.2,
}) {
  const harmonics = 6;
  final harmonicClass = [
    for (var h = 1; h <= harmonics; h++) (12 * math.log(h) / math.ln2).round() % 12,
  ];
  final templates = <ChordTemplate>[];
  for (final quality in vocabulary.qualities) {
    for (var root = 0; root < 12; root++) {
      final raw = Float64List(12);
      var mask = 0;
      for (final interval in quality.intervals) {
        final pc = (root + interval) % 12;
        mask |= 1 << pc;
        var amp = 1.0;
        for (var h = 0; h < harmonics; h++) {
          raw[(pc + harmonicClass[h]) % 12] += amp;
          amp *= harmonicDecay;
        }
      }
      templates.add(ChordTemplate._(root, quality, mask, standardize(raw)!));
    }
  }
  return templates;
}

/// Centre et réduit un vecteur (moyenne nulle, norme euclidienne 1). Null si
/// le vecteur est constant (aucune information tonale).
Float64List? standardize(List<double> v) {
  var mean = 0.0;
  for (final x in v) {
    mean += x;
  }
  mean /= v.length;
  final out = Float64List(v.length);
  var norm = 0.0;
  for (var i = 0; i < v.length; i++) {
    final d = v[i] - mean;
    out[i] = d;
    norm += d * d;
  }
  if (norm < 1e-12) return null;
  norm = math.sqrt(norm);
  for (var i = 0; i < out.length; i++) {
    out[i] /= norm;
  }
  return out;
}
