import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../codec/json_chord_chart_codec.dart';
import '../domain/chord_chart.dart';
import '../domain/song.dart';

/// Charge le catalogue et les grilles depuis les assets embarqués.
/// v0 : lecture seule. Remplacé par une base locale quand l'édition arrivera.
class CatalogRepository {
  const CatalogRepository();

  static const _codec = JsonChordChartCodec();

  Future<List<Song>> loadSongs() async {
    final raw = await rootBundle.loadString('assets/catalog.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return (map['songs'] as List<dynamic>).map(_songFromMap).toList();
  }

  Future<ChordChart> loadChart(Representation rep) async {
    final raw = await rootBundle.loadString(rep.assetPath);
    return _codec.decode(raw);
  }

  Song _songFromMap(dynamic e) {
    final m = e as Map<String, dynamic>;
    return Song(
      id: m['id'] as String,
      title: m['title'] as String,
      artist: m['artist'] as String?,
      tags: (m['tags'] as List<dynamic>? ?? []).cast<String>(),
      representations:
          (m['representations'] as List<dynamic>? ?? []).map(_repFromMap).toList(),
    );
  }

  Representation _repFromMap(dynamic e) {
    final m = e as Map<String, dynamic>;
    return Representation(
      id: m['id'] as String,
      type: representationTypeFromString(m['type'] as String),
      label: m['label'] as String?,
      assetPath: m['asset'] as String,
    );
  }
}
