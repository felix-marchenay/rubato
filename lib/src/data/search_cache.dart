import 'dart:convert';

import 'key_value_store.dart';
import 'local_db.dart';
import 'remote_catalog_service.dart';

/// Cache des recherches en ligne, posé sur [LocalDb].
///
/// But : **ne pas redemander au backend ce qu'on a déjà**. Une recherche coûte
/// cher (plusieurs sites scrapés, quelques secondes) alors que son résultat, lui,
/// ne bouge pratiquement pas. Une fois une requête en cache, l'écran l'affiche
/// instantanément et hors-ligne — contenus compris, donc on peut même ajouter le
/// morceau à sa bibliothèque sans réseau.
///
/// Stockage : une entrée par requête (clé normalisée), plus un index qui sert à
/// l'expiration et à l'éviction.
///
///   `search.<requête normalisée>` → {"query":…, "at":…, "songs":[…]}
///   `search.index`                → [{"key":…, "query":…, "at":…}, …]
class SearchCache {
  const SearchCache({this.db = const LocalDb()});

  final KeyValueStore db;

  /// Au-delà, l'entrée est considérée absente : les sites bougent, les grilles
  /// sont corrigées, autant refaire la recherche de temps en temps.
  static const maxAge = Duration(days: 7);

  /// Nombre de requêtes conservées (les plus anciennes sont évincées). Le web
  /// stocke dans `localStorage`, dont le quota est d'environ 5 Mo.
  static const maxEntries = 30;

  static const _indexKey = 'search.index';

  /// Deux formulations de la même recherche partagent leur entrée
  /// (« Creep  Radiohead » == « creep radiohead »).
  static String keyFor(String query) =>
      'search.${RemoteCatalogService.slug(query)}';

  /// Résultats en cache pour cette requête, ou `null` si absente ou périmée.
  Future<List<RemoteSong>?> read(String query) async {
    final raw = await db.read(keyFor(query));
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final at = DateTime.tryParse(data['at'] as String? ?? '');
      if (at == null || DateTime.now().difference(at) > maxAge) return null;
      final songs = (data['songs'] as List?)
              ?.map(RemoteSong.fromJson)
              .whereType<RemoteSong>()
              .toList() ??
          const <RemoteSong>[];
      return songs.isEmpty ? null : songs;
    } catch (_) {
      return null; // entrée corrompue : traitée comme absente
    }
  }

  /// Enregistre (ou remplace) les résultats d'une requête. Ne stocke rien si la
  /// recherche n'a rien donné : ça n'apprendrait rien et ça empêcherait de
  /// retenter plus tard.
  Future<void> write(String query, List<RemoteSong> songs) async {
    if (songs.isEmpty) return;
    final key = keyFor(query);
    final at = DateTime.now();
    final ok = await db.write(
      key,
      jsonEncode({
        'query': query,
        'at': at.toIso8601String(),
        'songs': [for (final s in songs) s.toJson()],
      }),
    );
    if (!ok) return; // stockage indisponible : on continue sans cache
    await _touchIndex(key: key, query: query, at: at);
  }

  /// Oublie une requête (bouton « actualiser » : on veut vraiment le réseau).
  Future<void> forget(String query) async {
    final key = keyFor(query);
    await db.delete(key);
    final entries = await _readIndex();
    entries.removeWhere((e) => e['key'] == key);
    await _writeIndex(entries);
  }

  /// Vide tout le cache (les entrées comme l'index).
  Future<void> clear() async {
    for (final e in await _readIndex()) {
      final key = e['key'];
      if (key is String) await db.delete(key);
    }
    await db.delete(_indexKey);
  }

  /// Les requêtes en cache, de la plus récente à la plus ancienne.
  Future<List<String>> recentQueries() async {
    final entries = await _readIndex();
    return [
      for (final e in entries.reversed)
        if (e['query'] is String) e['query'] as String,
    ];
  }

  // --- Index -----------------------------------------------------------------

  Future<void> _touchIndex({
    required String key,
    required String query,
    required DateTime at,
  }) async {
    final entries = await _readIndex();
    entries.removeWhere((e) => e['key'] == key);
    entries.add({'key': key, 'query': query, 'at': at.toIso8601String()});

    // Éviction des plus anciennes : l'index est trié par ordre d'écriture, donc
    // le surplus est en tête.
    while (entries.length > maxEntries) {
      final evicted = entries.removeAt(0);
      final evictedKey = evicted['key'];
      if (evictedKey is String) await db.delete(evictedKey);
    }
    await _writeIndex(entries);
  }

  Future<List<Map<String, dynamic>>> _readIndex() async {
    final raw = await db.read(_indexKey);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<Map<String, dynamic>> entries) =>
      db.write(_indexKey, jsonEncode(entries));
}
