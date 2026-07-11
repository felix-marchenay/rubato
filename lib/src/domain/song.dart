/// Un morceau et ses représentations. Cœur du modèle : 1 morceau -> N
/// représentations typées. En v0, seule [RepresentationType.chordGrid] est
/// réellement rendue, mais le modèle prévoit les autres.
library;

enum RepresentationType {
  chordGrid,
  tablature,
  lyrics,
  score,
  pdf,
  image,
  unknown,
}

RepresentationType representationTypeFromString(String s) {
  switch (s) {
    case 'chordGrid':
      return RepresentationType.chordGrid;
    case 'tablature':
      return RepresentationType.tablature;
    case 'lyrics':
      return RepresentationType.lyrics;
    case 'score':
      return RepresentationType.score;
    case 'pdf':
      return RepresentationType.pdf;
    case 'image':
      return RepresentationType.image;
    default:
      return RepresentationType.unknown;
  }
}

/// Réciproque de [representationTypeFromString] (sérialisation, appels réseau).
String representationTypeToString(RepresentationType t) {
  switch (t) {
    case RepresentationType.chordGrid:
      return 'chordGrid';
    case RepresentationType.tablature:
      return 'tablature';
    case RepresentationType.lyrics:
      return 'lyrics';
    case RepresentationType.score:
      return 'score';
    case RepresentationType.pdf:
      return 'pdf';
    case RepresentationType.image:
      return 'image';
    case RepresentationType.unknown:
      return 'unknown';
  }
}

/// Une façon de présenter un morceau. En v0, [assetPath] pointe vers un chart
/// JSON embarqué décodé par un codec.
class Representation {
  final String id;
  final RepresentationType type;
  final String? label;
  final String assetPath;

  const Representation({
    required this.id,
    required this.type,
    this.label,
    required this.assetPath,
  });
}

class Song {
  final String id;
  final String title;
  final String? artist;
  final List<String> tags;
  final List<Representation> representations;

  const Song({
    required this.id,
    required this.title,
    this.artist,
    this.tags = const [],
    this.representations = const [],
  });

  /// Première représentation « grille d'accords », ou null.
  Representation? get primaryChordGrid => _first(RepresentationType.chordGrid);

  /// Première représentation « paroles + accords » (ChordPro), ou null.
  Representation? get primaryLyrics => _first(RepresentationType.lyrics);

  /// Première représentation « mélodie / partition » (notation ABC), ou null.
  Representation? get primaryScore => _first(RepresentationType.score);

  Representation? _first(RepresentationType type) {
    for (final r in representations) {
      if (r.type == type) return r;
    }
    return null;
  }
}
