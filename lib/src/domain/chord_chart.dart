/// Modèle de domaine de la représentation « grille d'accords » (style iReal Pro,
/// sans paroles). Indépendant de tout format de stockage : la (dé)sérialisation
/// est assurée par un [ChordChartCodec].
library;

/// Classe de hauteur (0..11, C = 0). Permet la transposition future,
/// indépendamment de l'orthographe (C# / Db).
class PitchClass {
  final int value;
  const PitchClass(this.value);

  static const Map<String, int> _byName = {
    'C': 0, 'B#': 0,
    'C#': 1, 'Db': 1,
    'D': 2,
    'D#': 3, 'Eb': 3,
    'E': 4, 'Fb': 4,
    'F': 5, 'E#': 5,
    'F#': 6, 'Gb': 6,
    'G': 7,
    'G#': 8, 'Ab': 8,
    'A': 9,
    'A#': 10, 'Bb': 10,
    'B': 11, 'Cb': 11,
  };

  static PitchClass? parse(String note) {
    final v = _byName[note];
    return v == null ? null : PitchClass(v % 12);
  }

  PitchClass transpose(int semitones) => PitchClass((value + semitones) % 12);

  @override
  bool operator ==(Object other) => other is PitchClass && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Un accord. On conserve l'orthographe d'origine (affichage) tout en exposant
/// la classe de hauteur parsée (transposition future).
class Chord {
  /// "Bb", "C#", "N.C."…
  final String rootName;

  /// Qualité brute, vocabulaire aligné iReal Pro : "^7", "-7", "h7", "o7",
  /// "7b9", "sus", ""…
  final String quality;

  /// Basse d'un accord slash, ex. "E" dans C/E. Null sinon.
  final String? bassName;

  const Chord({required this.rootName, this.quality = '', this.bassName});

  bool get isNoChord => rootName == 'N.C.';

  PitchClass? get root => PitchClass.parse(rootName);
  PitchClass? get bass => bassName == null ? null : PitchClass.parse(bassName!);

  /// Symbole brut tel que saisi (proche iReal Pro).
  String get raw =>
      bassName == null ? '$rootName$quality' : '$rootName$quality/$bassName';
}

/// Une mesure : un ou plusieurs accords.
class Bar {
  final List<Chord> chords;
  const Bar(this.chords);
}

/// Une section (couplet/refrain/repère). Le label n'est pas rendu en v0 mais
/// sert déjà à regrouper les mesures.
class Section {
  final String? label;
  final List<Bar> bars;
  const Section({this.label, required this.bars});
}

/// Signature rythmique, ex. 4/4.
class TimeSignature {
  final int beats;
  final int unit;
  const TimeSignature(this.beats, this.unit);

  factory TimeSignature.parse(String s) {
    final parts = s.split('/');
    return TimeSignature(int.parse(parts[0].trim()), int.parse(parts[1].trim()));
  }

  @override
  String toString() => '$beats/$unit';
}

/// Tonalité, ex. "Gm", "Bb", "C".
class MusicKey {
  final String name;
  const MusicKey(this.name);
  @override
  String toString() => name;
}

/// La grille d'accords complète.
class ChordChart {
  final MusicKey? key;
  final TimeSignature? time;
  final List<Section> sections;

  const ChordChart({this.key, this.time, required this.sections});

  /// Toutes les mesures, sections aplaties (pratique pour un rendu simple).
  Iterable<Bar> get allBars => sections.expand((s) => s.bars);
}
