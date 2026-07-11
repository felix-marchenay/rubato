import '../domain/chord_chart.dart';

/// Met en forme un accord pour l'affichage. Mappe le vocabulaire iReal Pro
/// (^, -, h, o) vers des symboles lisibles. Rendu texte simple pour la v0.
class ChordFormat {
  static String display(Chord c) {
    if (c.isNoChord) return 'N.C.';
    var q = c.quality;
    q = q.replaceAll('^', 'Δ'); // Δ  majeur 7
    q = q.replaceAll('h', 'ø'); // ø  demi-diminué
    q = q.replaceAll('o', '°'); // °  diminué
    q = q.replaceAll('-', 'm'); //        mineur
    final bass = c.bassName == null ? '' : '/${c.bassName}';
    return '${c.rootName}$q$bass';
  }
}
