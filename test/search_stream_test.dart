import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/data/remote_catalog_service.dart';
import 'package:mscore/src/data/sse.dart';
import 'package:mscore/src/domain/song.dart';

/// Faux canal SSE : rejoue des trames données, sans réseau ni plateforme.
class FakeChannel implements SseChannel {
  FakeChannel(this.frames);
  final List<SseFrame> frames;
  Uri? requested;

  @override
  Stream<SseFrame> connect(Uri uri) {
    requested = uri;
    return Stream.fromIterable(frames);
  }
}

/// Canal qui n'existe pas (plateforme sans transport) → l'appelant doit basculer
/// sur la recherche batch.
class UnsupportedChannel implements SseChannel {
  @override
  Stream<SseFrame> connect(Uri uri) =>
      throw UnsupportedError('pas de SSE ici');
}

SseFrame result(String type, String title, String artist, String source) =>
    SseFrame(
      SseEvents.result,
      '{"type":"$type","title":"$title","artist":"$artist",'
          '"source":"$source","content":"{}"}',
    );

void main() {
  group('decodeSse', () {
    test('assemble les trames même découpées n\'importe où', () async {
      // Un flux réel arrive en morceaux arbitraires : ici une trame est coupée
      // au milieu de son JSON, et deux trames arrivent dans le même morceau.
      final chunks = Stream.fromIterable([
        'event: result\ndata: {"a":',
        '1}\n\nevent: source\ndata: {"source":"x"}\n\nevent: do',
        'ne\ndata: {}\n\n',
      ]);

      final frames = await decodeSse(chunks).toList();

      expect(frames.map((f) => f.event).toList(),
          [SseEvents.result, SseEvents.source, SseEvents.done]);
      expect(frames.first.data, '{"a":1}');
    });

    test('ignore les blocs sans événement nommé (commentaires, pings)',
        () async {
      final frames =
          await decodeSse(Stream.value(': ping\n\ndata: orphelin\n\n')).toList();
      expect(frames, isEmpty);
    });
  });

  group('searchStream', () {
    test('agrège les résultats au fil de l\'eau, un morceau à la fois',
        () async {
      final channel = FakeChannel([
        result('chordGrid', 'So What', 'Miles Davis', 'irealpro'),
        SseFrame(SseEvents.source,
            '{"source":"irealpro","count":1,"found":1,"ms":16}'),
        // Mêmes titre/artiste : ce sont les paroles DU MÊME morceau → un seul
        // résultat affiché, avec deux représentations.
        result('lyrics', 'So What', 'Miles Davis', 'lrclib'),
        result('chordGrid', 'Creep', 'Radiohead', 'echords'),
        SseFrame(SseEvents.source,
            '{"source":"echords","count":1,"found":2,"ms":900,"error":null}'),
        const SseFrame(SseEvents.done, '{"chordGrids":2,"lyrics":1}'),
      ]);

      final events = await RemoteCatalogService(transport: channel)
          .searchStream('so what')
          .toList();

      // La requête est bien passée au bon endpoint.
      expect(channel.requested?.path, '/search/stream');
      expect(channel.requested?.queryParameters['q'], 'so what');

      // Trois lots de résultats (un par trame `result`), donc affichage
      // progressif ; le dernier lot contient l'état complet.
      final songLists = events.whereType<SearchSongs>().toList();
      expect(songLists.length, 3);
      expect(songLists[0].songs.length, 1);
      expect(songLists.last.songs.length, 2);

      final soWhat = songLists.last.songs.first;
      expect(soWhat.title, 'So What');
      expect(soWhat.id, 'so-what-miles-davis');
      expect(soWhat.has(RepresentationType.chordGrid), isTrue);
      expect(soWhat.has(RepresentationType.lyrics), isTrue);
      expect(soWhat.sourceOf(RepresentationType.chordGrid), 'irealpro');
      expect(soWhat.sourceOf(RepresentationType.lyrics), 'lrclib');

      // L'avancement des sources est remonté tel quel.
      final progress = events.whereType<SearchSourceDone>().toList();
      expect(progress.length, 2);
      expect(progress.first.progress.source, 'irealpro');
      expect(progress.first.progress.failed, isFalse);

      expect(events.last, isA<SearchDone>());
    });

    test('une trame illisible n\'interrompt pas le flux', () async {
      final channel = FakeChannel([
        const SseFrame(SseEvents.result, 'pas du json'),
        result('chordGrid', 'Creep', 'Radiohead', 'echords'),
        const SseFrame(SseEvents.done, '{}'),
      ]);

      final events = await RemoteCatalogService(transport: channel)
          .searchStream('creep')
          .toList();

      final songs = events.whereType<SearchSongs>().last.songs;
      expect(songs.length, 1);
      expect(songs.first.title, 'Creep');
    });

    test('la première source d\'un type gagne', () async {
      final channel = FakeChannel([
        result('chordGrid', 'Creep', 'Radiohead', 'irealpro'),
        result('chordGrid', 'Creep', 'Radiohead', 'echords'),
        const SseFrame(SseEvents.done, '{}'),
      ]);

      final events = await RemoteCatalogService(transport: channel)
          .searchStream('creep')
          .toList();

      final songs = events.whereType<SearchSongs>().last.songs;
      expect(songs.length, 1);
      expect(songs.first.sourceOf(RepresentationType.chordGrid), 'irealpro');
    });
  });

  test('sans transport SSE, la recherche ne casse pas (repli batch)', () async {
    // Le repli appelle /search en HTTP : sans backend joignable dans les tests,
    // on vérifie seulement qu'on ne part pas en UnsupportedError non attrapée.
    final stream =
        RemoteCatalogService(transport: UnsupportedChannel()).searchStream('x');
    await expectLater(stream.toList(), throwsA(isNot(isA<UnsupportedError>())));
  });
}
