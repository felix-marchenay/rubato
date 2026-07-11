import '../domain/lyric_sheet.dart';

/// Décode le format **ChordPro** (standard de facto pour paroles + accords) en
/// [LyricSheet]. Sous-ensemble supporté :
///
///  - accords en ligne entre crochets : `[C]Twinkle [F]twinkle`
///  - directives méta : `{key: C}`, `{time: 4/4}`, `{title: …}`, `{artist: …}`
///  - repères de section : `{comment: …}` / `{c: …}`,
///    `{start_of_chorus}` / `{soc}` (→ « Refrain »),
///    `{start_of_verse}` / `{sov}` (→ « Couplet »)
///  - ligne vide = séparation de strophe
class ChordProCodec {
  const ChordProCodec();

  static final _bracket = RegExp(r'\[([^\]]*)\]');

  LyricSheet decode(String source) {
    String? key;
    String? time;
    final sections = <LyricSection>[];

    String? currentLabel;
    var currentLines = <LyricLine>[];

    void flush() {
      if (currentLines.isNotEmpty || currentLabel != null) {
        sections.add(LyricSection(label: currentLabel, lines: currentLines));
      }
      currentLabel = null;
      currentLines = <LyricLine>[];
    }

    void startSection(String? label) {
      flush();
      currentLabel = label;
    }

    for (final rawLine in source.split('\n')) {
      final line = rawLine.replaceAll('\r', '');
      final trimmed = line.trim();

      // Commentaire ChordPro : ligne ignorée au rendu.
      if (trimmed.startsWith('#')) continue;

      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final body = trimmed.substring(1, trimmed.length - 1).trim();
        final sep = body.indexOf(':');
        final name = (sep >= 0 ? body.substring(0, sep) : body).trim().toLowerCase();
        final value = sep >= 0 ? body.substring(sep + 1).trim() : '';
        switch (name) {
          case 'key':
            key = value;
          case 'time':
            time = value;
          case 'comment':
          case 'c':
            startSection(value.isEmpty ? null : value);
          case 'start_of_chorus':
          case 'soc':
            startSection(value.isEmpty ? 'Refrain' : value);
          case 'start_of_verse':
          case 'sov':
            startSection(value.isEmpty ? 'Couplet' : value);
          default:
            // title, artist, end_of_*, autres directives : ignorées au rendu.
            break;
        }
        continue;
      }

      if (trimmed.isEmpty) {
        // Espace entre strophes (pas de blanc en tête de section).
        if (currentLines.isNotEmpty && !currentLines.last.isBlank) {
          currentLines.add(const LyricLine([]));
        }
        continue;
      }

      currentLines.add(_parseLine(line));
    }

    flush();
    return LyricSheet(key: key, time: time, sections: sections);
  }

  /// Construit une feuille à partir de paroles brutes (sans accords) : une
  /// ligne de texte = une ligne de chant, les lignes vides séparent les
  /// strophes. Utilisé pour les paroles récupérées en ligne (LRCLIB).
  LyricSheet plainText(String text, {String? key, String? time}) {
    final lines = <LyricLine>[];
    for (final raw in text.split('\n')) {
      final t = raw.replaceAll('\r', '');
      if (t.trim().isEmpty) {
        if (lines.isNotEmpty && !lines.last.isBlank) {
          lines.add(const LyricLine([]));
        }
      } else {
        lines.add(LyricLine([LyricSegment(text: t)]));
      }
    }
    return LyricSheet(
      key: key,
      time: time,
      sections: [LyricSection(label: null, lines: lines)],
    );
  }

  LyricLine _parseLine(String line) {
    final segments = <LyricSegment>[];
    var last = 0;
    String? pendingChord;

    for (final m in _bracket.allMatches(line)) {
      final text = line.substring(last, m.start);
      if (text.isNotEmpty || pendingChord != null) {
        segments.add(LyricSegment(chord: pendingChord, text: text));
      }
      pendingChord = m.group(1);
      last = m.end;
    }

    final tail = line.substring(last);
    if (tail.isNotEmpty || pendingChord != null) {
      segments.add(LyricSegment(chord: pendingChord, text: tail));
    }

    return LyricLine(segments);
  }
}
