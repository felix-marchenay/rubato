/// Guide des styles : une fiche « antisèche » par style de musique (progressions,
/// tempo, gammes, conseils de jeu). Contenu statique, cf. `data/style_guides.dart`.
library;

import '../codec/chord_parser.dart';
import 'chord_chart.dart';

/// Familles de styles, dans l'ordre d'affichage du guide.
enum StyleFamily {
  bluesJazz('Blues & jazz'),
  rockPop('Rock & pop'),
  soulFunk('Soul, funk & groove'),
  latinWorld('Latin & monde'),
  folkTrad('Folk, country & trad'),
  urban('Urbain & électro');

  const StyleFamily(this.label);
  final String label;
}

/// Plage de tempo usuelle, en BPM.
class TempoRange {
  final int min;
  final int max;
  const TempoRange(this.min, this.max);

  @override
  String toString() => min == max ? '$min' : '$min–$max';
}

/// Une progression type. Les accords sont écrits dans la tonalité de référence
/// du style ([StyleGuide.tonic]), au vocabulaire iReal (`-` min, `^` maj7,
/// `h` ø, `o` °) ; une chaîne = une mesure, accords séparés par des espaces.
class StyleProgression {
  final String name;

  /// Degrés en chiffres romains, ex. « ii – V – I ».
  final String degrees;
  final List<String> bars;
  final String? tip;

  const StyleProgression({
    required this.name,
    required this.degrees,
    required this.bars,
    this.tip,
  });

  /// Mesures parsées, transposées de la tonique [from] vers [to].
  List<Bar> barsIn(String from, String to) => [
        for (final bar in bars)
          Bar([
            for (final symbol in bar.split(' ').where((s) => s.isNotEmpty))
              transposeChord(ChordParser.parse(symbol), from, to),
          ]),
      ];
}

/// Une fiche de style.
class StyleGuide {
  final String id;
  final String name;
  final StyleFamily family;

  /// L'esprit du style en une phrase.
  final String tagline;

  /// Origine : lieu · époque.
  final String origin;
  final TempoRange tempo;

  /// Mesure, ex. « 4/4 », « 12/8 ».
  final String meter;

  /// Le placement rythmique, ex. « croches swing (ternaire) ».
  final String feel;

  /// Tonique de référence des progressions (C, A, E…) : point de départ de la
  /// transposition.
  final String tonic;

  /// Tonalités courantes, pour info.
  final List<String> keys;
  final List<StyleProgression> progressions;
  final List<String> scales;

  /// Accompagnement, placement, groove.
  final List<String> rhythm;

  /// Mélodie et improvisation.
  final List<String> melody;

  /// Basse et batterie.
  final List<String> groove;
  final List<String> sound;
  final List<String> pitfalls;
  final List<String> artists;

  /// Morceaux de référence à écouter (« Titre — Artiste »).
  final List<String> listen;

  const StyleGuide({
    required this.id,
    required this.name,
    required this.family,
    required this.tagline,
    required this.origin,
    required this.tempo,
    required this.meter,
    required this.feel,
    required this.tonic,
    required this.keys,
    required this.progressions,
    required this.scales,
    required this.rhythm,
    required this.melody,
    required this.groove,
    required this.sound,
    required this.pitfalls,
    required this.artists,
    required this.listen,
  });

  /// Première mesure citée (« Reel 4/4 · jig 6/8 » → « 4/4 »), pour une grille.
  String? get timeSignature =>
      RegExp(r'\d+/\d+').firstMatch(meter)?.group(0);

  /// Grille jouable (mode entraînement) d'une progression, tonique [to].
  ChordChart chartOf(StyleProgression progression, String to) {
    final time = timeSignature;
    return ChordChart(
      key: MusicKey(to),
      time: time == null ? null : TimeSignature.parse(time),
      sections: [Section(bars: progression.barsIn(tonic, to))],
    );
  }
}

/// Toniques proposées au transpositeur.
const transposeTonics = [
  'C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
];

/// Écart montant (0..11) entre deux toniques.
int semitonesBetween(String from, String to) =>
    (PitchClass.parse(to)!.value - PitchClass.parse(from)!.value) % 12;

const _letters = 'CDEFGAB';
const _letterPitch = [0, 2, 4, 5, 7, 9, 11];

/// Transpose une note de la tonique [from] vers [to] en gardant sa fonction :
/// la lettre avance d'autant que celle de la tonique (un ♭VII reste un ♭VII :
/// Bb en C → Db en Eb). Doubles altérations et Fb/Cb/E#/B# sont simplifiées.
String transposeNote(String note, String from, String to) {
  final pitch = PitchClass.parse(note);
  if (pitch == null) return note;
  final target = pitch.transpose(semitonesBetween(from, to));
  final letterShift = _letters.indexOf(to[0]) - _letters.indexOf(from[0]);
  final letterIndex = (_letters.indexOf(note[0]) + letterShift) % 7;
  final letter = _letters[letterIndex];
  var accidental = (target.value - _letterPitch[letterIndex]) % 12;
  if (accidental > 6) accidental -= 12;
  final spelled = switch (accidental) {
    0 => letter,
    1 => '$letter#',
    -1 => '${letter}b',
    _ => null,
  };
  if (spelled == null || const {'Fb', 'Cb', 'E#', 'B#'}.contains(spelled)) {
    return target.name(flats: !const {'D', 'E', 'A', 'B', 'F#'}.contains(to));
  }
  return spelled;
}

Chord transposeChord(Chord chord, String from, String to) => Chord(
      rootName: transposeNote(chord.rootName, from, to),
      quality: chord.quality,
      bassName:
          chord.bassName == null ? null : transposeNote(chord.bassName!, from, to),
    );
