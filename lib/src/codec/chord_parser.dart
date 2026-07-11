import '../domain/chord_chart.dart';

/// Parse un symbole d'accord textuel (vocabulaire aligné iReal Pro) en [Chord].
/// Exemples : "Bb^7", "C-7", "G7b9", "Ah7", "C/E", "n" (N.C.).
class ChordParser {
  static final RegExp _root = RegExp(r'^([A-G])([#b]?)(.*)$');

  static Chord parse(String symbol) {
    final s = symbol.trim();
    if (s.isEmpty || s == 'n' || s.toUpperCase() == 'N.C.') {
      return const Chord(rootName: 'N.C.');
    }

    String main = s;
    String? bass;
    final slash = s.indexOf('/');
    if (slash > 0) {
      main = s.substring(0, slash);
      bass = s.substring(slash + 1).trim();
    }

    final m = _root.firstMatch(main);
    if (m == null) {
      // Racine non reconnue : on garde le texte brut comme "racine" pour ne
      // rien perdre à l'affichage.
      return Chord(rootName: main, bassName: bass);
    }

    final root = '${m.group(1)}${m.group(2)}';
    final quality = m.group(3) ?? '';
    return Chord(rootName: root, quality: quality, bassName: bass);
  }
}
