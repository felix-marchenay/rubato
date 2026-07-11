import 'dart:convert';

import '../domain/chord_chart.dart';
import 'chord_chart_codec.dart';
import 'chord_parser.dart';

/// Codec JSON « maison » de la v0. Format lisible et éditable à la main :
/// ```json
/// {
///   "key": "Gm",
///   "time": "4/4",
///   "sections": [
///     { "label": "A", "bars": [ {"chords": ["C-7"]}, {"chords": ["F7"]} ] }
///   ]
/// }
/// ```
class JsonChordChartCodec implements ChordChartCodec {
  const JsonChordChartCodec();

  @override
  ChordChart decode(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    return _chartFromMap(map);
  }

  @override
  String encode(ChordChart chart) => jsonEncode(_chartToMap(chart));

  ChordChart _chartFromMap(Map<String, dynamic> map) {
    final key = map['key'] as String?;
    final time = map['time'] as String?;
    final sections = (map['sections'] as List<dynamic>? ?? [])
        .map((s) => _sectionFromMap(s as Map<String, dynamic>))
        .toList();
    return ChordChart(
      key: key == null ? null : MusicKey(key),
      time: time == null ? null : TimeSignature.parse(time),
      sections: sections,
    );
  }

  Section _sectionFromMap(Map<String, dynamic> map) {
    final bars = (map['bars'] as List<dynamic>? ?? [])
        .map((b) => _barFromMap(b as Map<String, dynamic>))
        .toList();
    return Section(label: map['label'] as String?, bars: bars);
  }

  Bar _barFromMap(Map<String, dynamic> map) {
    final chords = (map['chords'] as List<dynamic>? ?? [])
        .map((c) => ChordParser.parse(c as String))
        .toList();
    return Bar(chords);
  }

  Map<String, dynamic> _chartToMap(ChordChart chart) => {
        if (chart.key != null) 'key': chart.key!.name,
        if (chart.time != null) 'time': chart.time!.toString(),
        'sections': [
          for (final s in chart.sections)
            {
              if (s.label != null) 'label': s.label,
              'bars': [
                for (final b in s.bars)
                  {'chords': [for (final c in b.chords) c.raw]},
              ],
            },
        ],
      };
}
