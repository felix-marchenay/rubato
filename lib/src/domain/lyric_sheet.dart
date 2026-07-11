/// Modèle de domaine de la représentation « paroles + accords » (type ChordPro).
/// Indépendant du format de stockage : la (dé)sérialisation est assurée par un
/// codec (voir [ChordProCodec]).
library;

/// Un fragment de ligne : un morceau de texte, précédé (au-dessus) d'un accord
/// optionnel. `[C]Twinkle` → segment(chord: "C", text: "Twinkle").
class LyricSegment {
  /// Accord affiché au-dessus du texte, ou null si le texte n'en porte pas.
  final String? chord;

  /// Texte des paroles (peut être vide si l'accord tombe en fin de ligne).
  final String text;

  const LyricSegment({this.chord, required this.text});
}

/// Une ligne de paroles, découpée en segments accord/texte.
class LyricLine {
  final List<LyricSegment> segments;
  const LyricLine(this.segments);

  /// Ligne vide : sert d'espace entre les strophes.
  bool get isBlank => segments.isEmpty;
}

/// Une section (couplet, refrain, pont…) : un label optionnel + ses lignes.
class LyricSection {
  final String? label;
  final List<LyricLine> lines;
  const LyricSection({this.label, required this.lines});
}

/// La feuille paroles + accords complète.
class LyricSheet {
  final String? key;
  final String? time;
  final List<LyricSection> sections;

  const LyricSheet({this.key, this.time, required this.sections});
}
