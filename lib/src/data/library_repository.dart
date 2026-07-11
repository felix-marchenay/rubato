import 'dart:convert';

import '../codec/chordpro_codec.dart';
import '../codec/json_chord_chart_codec.dart';
import '../domain/chord_chart.dart';
import '../domain/lyric_sheet.dart';
import '../domain/song.dart';
import 'catalog_repository.dart';
import 'user_library_store.dart';

/// Combine le catalogue embarqué ([CatalogRepository], lecture seule) et la
/// bibliothèque personnelle ([UserLibraryStore], alimentée par la recherche en
/// ligne). Expose **les mêmes méthodes** que [CatalogRepository] pour être
/// injecté à sa place dans l'UI, plus [addRepresentation] pour l'ajout.
///
/// Une représentation issue de la bibliothèque perso porte un `assetPath`
/// sentinelle `store:<songId>` ; les autres pointent vers un asset embarqué.
class LibraryRepository {
  final CatalogRepository catalog;
  final UserLibraryStore store;

  const LibraryRepository({
    this.catalog = const CatalogRepository(),
    this.store = const UserLibraryStore(),
  });

  static const _chartCodec = JsonChordChartCodec();
  static const _chordPro = ChordProCodec();
  static const _storePrefix = 'store:';

  /// Fabrique une [Representation] adossée à la bibliothèque perso (contenu lu
  /// depuis [store]). Utilisée par l'écran de recherche pour ouvrir un morceau
  /// tout juste ajouté.
  static Representation storeRepresentation(
          String songId, RepresentationType type) =>
      Representation(
        id: '$songId-${representationTypeToString(type)}',
        type: type,
        assetPath: '$_storePrefix$songId',
      );

  // --- Lecture des morceaux (fusion assets + perso) -----------------------

  Future<List<Song>> loadSongs() async {
    final assets = await catalog.loadSongs();
    final user = await _userSongs();
    final userById = {for (final s in user) s.id: s};
    final assetIds = <String>{};

    final merged = <Song>[];
    for (final a in assets) {
      assetIds.add(a.id);
      final u = userById[a.id];
      merged.add(u == null ? a : _merge(a, u));
    }
    // Morceaux ajoutés absents des assets : en tête (les plus récents pour l'utilisateur).
    final extras = user.where((s) => !assetIds.contains(s.id)).toList();
    return [...extras, ...merged];
  }

  Song _merge(Song asset, Song user) => Song(
        id: asset.id,
        title: asset.title,
        artist: asset.artist ?? user.artist,
        tags: asset.tags,
        // Reps perso en premier → priorité pour primaryChordGrid/Lyrics/Score.
        representations: [...user.representations, ...asset.representations],
      );

  Future<List<Song>> _userSongs() async {
    final raw = await store.readIndex();
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['songs'] : decoded;
      if (list is! List) return const [];
      return list.whereType<Map>().map(_songFromIndex).toList();
    } catch (_) {
      return const [];
    }
  }

  Song _songFromIndex(Map entry) {
    final id = entry['id'] as String? ?? '';
    final types =
        (entry['types'] as List?)?.whereType<String>().toList() ?? const [];
    final reps = <Representation>[];
    for (final t in types) {
      final type = representationTypeFromString(t);
      if (type == RepresentationType.unknown) continue;
      reps.add(storeRepresentation(id, type));
    }
    final artist = entry['artist'] as String?;
    return Song(
      id: id,
      title: entry['title'] as String? ?? id,
      artist: (artist != null && artist.isNotEmpty) ? artist : null,
      tags: (entry['tags'] as List?)?.whereType<String>().toList() ?? const [],
      representations: reps,
    );
  }

  // --- Chargement d'une représentation ------------------------------------

  bool _isStore(Representation r) => r.assetPath.startsWith(_storePrefix);
  String _sid(Representation r) => r.assetPath.substring(_storePrefix.length);

  Future<ChordChart> loadChart(Representation rep) async {
    if (_isStore(rep)) {
      final raw = await store.read(_sid(rep), 'chordGrid');
      if (raw == null) throw Exception('Grille absente du stockage local');
      return _chartCodec.decode(raw);
    }
    return catalog.loadChart(rep);
  }

  Future<LyricSheet> loadLyrics(Representation rep) async {
    if (_isStore(rep)) {
      final raw = await store.read(_sid(rep), 'lyrics');
      if (raw == null) throw Exception('Paroles absentes du stockage local');
      return _chordPro.decode(raw);
    }
    return catalog.loadLyrics(rep);
  }

  Future<String> loadScoreSource(Representation rep) async {
    if (_isStore(rep)) {
      final raw = await store.read(_sid(rep), 'score');
      if (raw == null) throw Exception('Mélodie absente du stockage local');
      return raw;
    }
    return catalog.loadScoreSource(rep);
  }

  // --- Ajout depuis la recherche en ligne ---------------------------------

  /// Enregistre le contenu d'une représentation et met à jour l'index.
  /// Retourne `false` si le stockage local est indisponible (le contenu
  /// n'est alors pas conservé).
  Future<bool> addRepresentation({
    required String songId,
    required String title,
    String? artist,
    List<String> tags = const [],
    required RepresentationType type,
    required String content,
  }) async {
    final typeStr = representationTypeToString(type);
    final ok = await store.write(songId, typeStr, content);
    if (!ok) return false;
    await _upsertIndex(
      songId: songId,
      title: title,
      artist: artist,
      tags: tags,
      type: typeStr,
    );
    return true;
  }

  Future<void> _upsertIndex({
    required String songId,
    required String title,
    String? artist,
    required List<String> tags,
    required String type,
  }) async {
    final raw = await store.readIndex();
    Map<String, dynamic> doc;
    try {
      final decoded = raw == null ? null : jsonDecode(raw);
      doc = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'version': 1, 'songs': <dynamic>[]};
    } catch (_) {
      doc = <String, dynamic>{'version': 1, 'songs': <dynamic>[]};
    }

    final songs = (doc['songs'] as List?)?.toList() ?? <dynamic>[];
    Map? entry;
    for (final e in songs) {
      if (e is Map && e['id'] == songId) {
        entry = e;
        break;
      }
    }
    if (entry == null) {
      entry = <String, dynamic>{
        'id': songId,
        'title': title,
        if (artist != null) 'artist': artist,
        'tags': tags,
        'types': <String>[],
      };
      songs.add(entry);
    } else {
      entry['title'] = title;
      if (artist != null) entry['artist'] = artist;
      if (tags.isNotEmpty) entry['tags'] = tags;
    }

    final types = <String>{
      ...?(entry['types'] as List?)?.whereType<String>(),
      type,
    };
    entry['types'] = types.toList();

    doc['songs'] = songs;
    doc['version'] = 1;
    await store.writeIndex(jsonEncode(doc));
  }
}
