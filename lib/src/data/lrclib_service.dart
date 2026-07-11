import 'dart:convert';

import 'package:http/http.dart' as http;

/// Source de paroles en ligne, adossée à l'API publique et gratuite de
/// **LRCLIB** (https://lrclib.net). Récupère les paroles brutes à l'exécution ;
/// rien n'est stocké dans le dépôt. Le texte des paroles reste la propriété de
/// ses ayants droit — LRCLIB ne fournit qu'un accès.
class LrclibService {
  const LrclibService();

  /// Cherche les paroles brutes (texte) d'un morceau. Retourne `null` si LRCLIB
  /// ne trouve rien. Lève une exception en cas d'erreur réseau/HTTP.
  Future<String?> fetchPlainLyrics({
    required String track,
    String? artist,
  }) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': track,
      if (artist != null && artist.isNotEmpty) 'artist_name': artist,
    });

    final resp = await http.get(uri, headers: {
      // LRCLIB demande un User-Agent identifiant l'application.
      'User-Agent': 'Rubato/0.1 (carnet d\'accords personnel)',
    });

    if (resp.statusCode != 200) {
      throw Exception('LRCLIB a répondu ${resp.statusCode}');
    }

    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is! List) return null;

    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final plain = item['plainLyrics'];
        if (plain is String && plain.trim().isNotEmpty) {
          return plain;
        }
      }
    }
    return null;
  }
}
