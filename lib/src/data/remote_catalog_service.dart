import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/song.dart';

/// URL de base du proxy d'agrégation. Surchargeable au build :
///   flutter run  --dart-define=RUBATO_API=http://localhost:8091
///   flutter build apk --dart-define=RUBATO_API=https://mon-proxy.example
const String _apiBase =
    String.fromEnvironment('RUBATO_API', defaultValue: 'http://localhost:8091');

/// Référence source d'une représentation (à passer à `/representation`).
class RemoteRef {
  final String source;
  final String ref;
  const RemoteRef({required this.source, required this.ref});
}

/// Un candidat renvoyé par la recherche en ligne : un morceau et les
/// représentations disponibles (avec leur source).
class RemoteSong {
  final String id;
  final String title;
  final String? artist;
  final Map<RepresentationType, RemoteRef> refs;

  const RemoteSong({
    required this.id,
    required this.title,
    this.artist,
    this.refs = const {},
  });

  bool has(RepresentationType type) => refs.containsKey(type);
  Iterable<RepresentationType> get available => refs.keys;
}

/// Client du proxy d'agrégation. Sans état, calqué sur [LrclibService] :
/// package `http`, décodage UTF-8, exception sur statut ≠ 200. Ajoute un
/// timeout (dette non reproduite de LrclibService).
class RemoteCatalogService {
  const RemoteCatalogService();

  Uri _uri(String path, Map<String, String> query) =>
      Uri.parse(_apiBase).replace(path: path, queryParameters: query);

  /// Recherche multi-sources. Lève une exception en cas d'erreur réseau/HTTP.
  Future<List<RemoteSong>> search(String query) async {
    final resp = await http
        .get(_uri('/search', {'q': query}))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('Recherche indisponible (HTTP ${resp.statusCode})');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final results = data is Map ? data['results'] : null;
    if (results is! List) return const [];
    return results.whereType<Map>().map(_songFromMap).toList();
  }

  /// Récupère le contenu d'une représentation au format pivot (chart JSON /
  /// ChordPro / ABC selon le type).
  Future<String> fetchRepresentation(
      RemoteRef ref, RepresentationType type) async {
    final resp = await http.get(_uri('/representation', {
      'type': representationTypeToString(type),
      'source': ref.source,
      'ref': ref.ref,
    })).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('Récupération impossible (HTTP ${resp.statusCode})');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final content = data is Map ? data['content'] : null;
    if (content is! String || content.isEmpty) {
      throw Exception('Contenu vide');
    }
    return content;
  }

  RemoteSong _songFromMap(Map m) {
    final refsJson = m['refs'];
    final refs = <RepresentationType, RemoteRef>{};
    if (refsJson is Map) {
      refsJson.forEach((k, v) {
        final type = representationTypeFromString(k as String);
        if (type == RepresentationType.unknown || v is! Map) return;
        refs[type] = RemoteRef(
          source: v['source'] as String? ?? '',
          ref: v['ref']?.toString() ?? '',
        );
      });
    }
    final artist = m['artist'] as String?;
    return RemoteSong(
      id: m['id'] as String? ?? '',
      title: m['title'] as String? ?? '',
      artist: (artist != null && artist.isNotEmpty) ? artist : null,
      refs: refs,
    );
  }
}
