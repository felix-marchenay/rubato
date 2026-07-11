import '../domain/chord_chart.dart';

/// Accord décomposé pour l'affichage gravé : racine, qualité (en exposant) et
/// basse d'un accord slash.
class ChordParts {
  final String root;
  final String quality;
  final String? bass;
  final bool isNoChord;

  const ChordParts({
    required this.root,
    required this.quality,
    this.bass,
    this.isNoChord = false,
  });
}

/// Met en forme un accord pour l'affichage. Mappe le vocabulaire iReal Pro
/// (^, -, h, o) vers des symboles lisibles (Δ, m, ø, °).
class ChordFormat {
  static String _mapQuality(String quality) {
    var q = quality;
    q = q.replaceAll('^', 'Δ'); // Δ  majeur 7
    q = q.replaceAll('h', 'ø'); // ø  demi-diminué
    q = q.replaceAll('o', '°'); // °  diminué
    q = q.replaceAll('-', 'm'); //    mineur
    return q;
  }

  /// Rendu texte simple (une seule chaîne).
  static String display(Chord c) {
    if (c.isNoChord) return 'N.C.';
    final bass = c.bassName == null ? '' : '/${c.bassName}';
    return '${c.rootName}${_mapQuality(c.quality)}$bass';
  }

  /// Rendu décomposé pour une mise en forme typographique (racine + exposant).
  static ChordParts parts(Chord c) {
    if (c.isNoChord) {
      return const ChordParts(root: 'N.C.', quality: '', isNoChord: true);
    }
    return ChordParts(
      root: c.rootName,
      quality: _mapQuality(c.quality),
      bass: c.bassName,
    );
  }
}
