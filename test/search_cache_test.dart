import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/data/key_value_store.dart';
import 'package:mscore/src/data/remote_catalog_service.dart';
import 'package:mscore/src/data/search_cache.dart';
import 'package:mscore/src/domain/song.dart';

/// Stockage en mémoire : même contrat que LocalDb, sans système de fichiers ni
/// navigateur (les vraies implémentations ne tournent pas en test unitaire).
class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};
  bool full = false; // simule un quota dépassé

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<bool> write(String key, String value) async {
    if (full) return false;
    data[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<List<String>> keys() async => data.keys.toList();
}

RemoteSong song(String title, String artist) => RemoteSong(
      id: '${RemoteCatalogService.slug(title)}-${RemoteCatalogService.slug(artist)}',
      title: title,
      artist: artist,
      contents: {
        RepresentationType.chordGrid:
            const RemoteContent(source: 'echords', content: '{"sections":[]}'),
      },
    );

void main() {
  test('relit ce qui a été écrit, contenus compris', () async {
    final store = MemoryStore();
    final cache = SearchCache(db: store);

    await cache.write('Creep Radiohead', [song('Creep', 'Radiohead')]);
    final read = await cache.read('Creep Radiohead');

    expect(read, isNotNull);
    expect(read!.single.title, 'Creep');
    final grid = read.single.contents[RepresentationType.chordGrid]!;
    expect(grid.source, 'echords');
    expect(grid.content, '{"sections":[]}');
  });

  test('deux formulations de la même requête partagent l\'entrée', () async {
    final cache = SearchCache(db: MemoryStore());
    await cache.write('creep radiohead', [song('Creep', 'Radiohead')]);

    // Casse et espaces superflus : même clé.
    expect(await cache.read('  Creep   RADIOHEAD '), isNotNull);
  });

  test('une requête inconnue renvoie null', () async {
    final cache = SearchCache(db: MemoryStore());
    expect(await cache.read('jamais cherché'), isNull);
  });

  test('une entrée périmée est traitée comme absente', () async {
    final store = MemoryStore();
    final cache = SearchCache(db: store);
    final old = DateTime.now().subtract(SearchCache.maxAge * 2);
    store.data[SearchCache.keyFor('vieux')] = jsonEncode({
      'query': 'vieux',
      'at': old.toIso8601String(),
      'songs': [song('Creep', 'Radiohead').toJson()],
    });

    expect(await cache.read('vieux'), isNull);
  });

  test('une entrée corrompue est traitée comme absente', () async {
    final store = MemoryStore();
    store.data[SearchCache.keyFor('casse')] = 'ceci n\'est pas du json';
    expect(await SearchCache(db: store).read('casse'), isNull);
  });

  test('une recherche vide n\'est pas mise en cache', () async {
    final store = MemoryStore();
    await SearchCache(db: store).write('rien', const []);
    expect(store.data, isEmpty);
  });

  test('forget efface l\'entrée et la sort de l\'index', () async {
    final store = MemoryStore();
    final cache = SearchCache(db: store);
    await cache.write('creep', [song('Creep', 'Radiohead')]);

    await cache.forget('creep');

    expect(await cache.read('creep'), isNull);
    expect(await cache.recentQueries(), isEmpty);
  });

  test('les requêtes récentes sortent de la plus récente à la plus ancienne',
      () async {
    final cache = SearchCache(db: MemoryStore());
    await cache.write('un', [song('Un', 'X')]);
    await cache.write('deux', [song('Deux', 'X')]);
    await cache.write('trois', [song('Trois', 'X')]);

    expect(await cache.recentQueries(), ['trois', 'deux', 'un']);
  });

  test('au-delà du plafond, les plus anciennes entrées sont évincées',
      () async {
    final store = MemoryStore();
    final cache = SearchCache(db: store);
    for (var i = 0; i < SearchCache.maxEntries + 3; i++) {
      await cache.write('requête $i', [song('Titre $i', 'X')]);
    }

    expect((await cache.recentQueries()).length, SearchCache.maxEntries);
    // Les trois premières ont disparu, la dernière est là.
    expect(await cache.read('requête 0'), isNull);
    expect(await cache.read('requête 2'), isNull);
    expect(await cache.read('requête ${SearchCache.maxEntries + 2}'), isNotNull);
  });

  test('un stockage indisponible ne fait pas échouer l\'écriture', () async {
    final store = MemoryStore()..full = true;
    final cache = SearchCache(db: store);

    await cache.write('creep', [song('Creep', 'Radiohead')]); // ne lève pas

    expect(await cache.read('creep'), isNull);
  });

  test('clear vide tout', () async {
    final store = MemoryStore();
    final cache = SearchCache(db: store);
    await cache.write('un', [song('Un', 'X')]);
    await cache.write('deux', [song('Deux', 'X')]);

    await cache.clear();

    expect(store.data, isEmpty);
    expect(await cache.recentQueries(), isEmpty);
  });
}
