import '../domain/chord_chart.dart';

/// Frontière de découplage : convertit un format de stockage <-> le modèle de
/// domaine [ChordChart]. Le reste de l'app ne dépend QUE du domaine.
///
/// Implémentations :
///  - [JsonChordChartCodec] : notre format JSON (v0).
///  - (plus tard) IRealProCodec : import/export du format iReal Pro.
abstract class ChordChartCodec {
  /// Décode le texte source (JSON, chaîne iReal Pro…) en [ChordChart].
  ChordChart decode(String source);

  /// Encode un [ChordChart] vers le format texte cible.
  String encode(ChordChart chart);
}
