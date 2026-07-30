import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/song.dart';
import 'sse.dart';
import 'sse_transport.dart';

/// URL de base du backend de recherche (**backend Go**, dossier `backend/`).
/// Surchargeable au build :
/// `--dart-define=RUBATO_API=http://192.168.1.20:8091`.
///
/// Par défaut le **backend déployé** (Fly.io) : c'est le seul qu'une app
/// installée sur un téléphone puisse joindre, `localhost` y désignant le
/// téléphone. En dev, le Makefile passe l'URL locale (`make web` →
/// `http://localhost:8091`, le backend de `make api-run`).
///
/// ⚠️ Le nom d'app vit dans `backend/fly.toml` ; `make apk` en dérive le
/// `--dart-define`, donc ce défaut-ci ne sert qu'à un `flutter build` lancé à la
/// main. Si le nom change là-bas, le changer ici aussi.
const String _apiBase = String.fromEnvironment(
  'RUBATO_API',
  defaultValue: 'https://rubato-backend.fly.dev',
);

/// Contenu d'une représentation renvoyé par la recherche, avec sa provenance.
///
/// Le backend embarque le contenu **directement dans les résultats** (au format
/// pivot : grille JSON, ChordPro ou ABC) : il n'y a pas d'aller-retour pour le
/// récupérer, et une fois en cache l'app n'a plus besoin du backend du tout.
class RemoteContent {
  final String source;
  final String content;
  const RemoteContent({required this.source, required this.content});

  Map<String, dynamic> toJson() => {'source': source, 'content': content};

  static RemoteContent? fromJson(Object? json) {
    if (json is! Map) return null;
    final content = json['content'];
    if (content is! String || content.isEmpty) return null;
    return RemoteContent(
      source: json['source'] as String? ?? '',
      content: content,
    );
  }
}

/// Un candidat de la recherche en ligne : un morceau et les représentations
/// trouvées (avec leur source et leur contenu).
class RemoteSong {
  final String id;
  final String title;
  final String? artist;
  final Map<RepresentationType, RemoteContent> contents;

  const RemoteSong({
    required this.id,
    required this.title,
    this.artist,
    this.contents = const {},
  });

  bool has(RepresentationType type) => contents.containsKey(type);
  Iterable<RepresentationType> get available => contents.keys;

  /// Source retenue pour un type (affichage : « Grille · echords »).
  String? sourceOf(RepresentationType type) => contents[type]?.source;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (artist != null) 'artist': artist,
        'contents': {
          for (final e in contents.entries)
            representationTypeToString(e.key): e.value.toJson(),
        },
      };

  static RemoteSong? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'] as String? ?? '';
    final title = json['title'] as String? ?? '';
    if (id.isEmpty || title.isEmpty) return null;
    final contents = <RepresentationType, RemoteContent>{};
    final raw = json['contents'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final type = representationTypeFromString('$k');
        final content = RemoteContent.fromJson(v);
        if (type != RepresentationType.unknown && content != null) {
          contents[type] = content;
        }
      });
    }
    final artist = json['artist'] as String?;
    return RemoteSong(
      id: id,
      title: title,
      artist: (artist != null && artist.isNotEmpty) ? artist : null,
      contents: contents,
    );
  }
}

/// Où en est une source pendant une recherche en flux (affiché sous la barre de
/// recherche : « echords ✓ 2 · cifraclub … »).
class SourceProgress {
  final String source;
  final int count;
  final int ms;
  final String? error;

  const SourceProgress({
    required this.source,
    required this.count,
    required this.ms,
    this.error,
  });

  bool get failed => error != null;
}

/// Ce que rend [RemoteCatalogService.searchStream] au fil de l'eau. Trois
/// natures d'événement, calquées sur celles du backend.
sealed class SearchEvent {
  const SearchEvent();
}

/// La liste des morceaux vient de changer (nouveau résultat fusionné).
class SearchSongs extends SearchEvent {
  final List<RemoteSong> songs;
  const SearchSongs(this.songs);
}

/// Une source a fini (ou échoué).
class SearchSourceDone extends SearchEvent {
  final SourceProgress progress;
  const SearchSourceDone(this.progress);
}

/// Le flux est terminé : plus rien n'arrivera.
class SearchDone extends SearchEvent {
  const SearchDone();
}

/// Client du backend Go.
///
/// Deux modes :
///  - [searchStream] — **le mode normal** : SSE, les résultats s'affichent au
///    fur et à mesure (le corpus iReal répond en millisecondes, un site scrapé
///    en secondes) ;
///  - [search] — batch d'un seul bloc, utilisé comme repli si la plateforme n'a
///    pas de transport SSE.
class RemoteCatalogService {
  const RemoteCatalogService({this.transport = const SseTransport()});

  final SseChannel transport;

  /// Correspondance entre le vocabulaire du backend et les types du domaine.
  static const _types = {
    'chordGrid': RepresentationType.chordGrid,
    'lyrics': RepresentationType.lyrics,
    'score': RepresentationType.score,
  };

  /// Listes de la réponse batch `/search`, même correspondance.
  static const _lists = {
    'chordGrids': RepresentationType.chordGrid,
    'lyrics': RepresentationType.lyrics,
    'melodies': RepresentationType.score,
  };

  Uri _uri(String path, Map<String, String> query) =>
      Uri.parse(_apiBase).replace(path: path, queryParameters: query);

  /// Recherche **en flux**. Émet une liste de morceaux enrichie à chaque
  /// résultat reçu (l'app n'a qu'à afficher la dernière), l'avancement de chaque
  /// source, puis [SearchDone].
  ///
  /// En cas d'absence de transport SSE (plateforme sans `EventSource` ni
  /// `dart:io`), retombe automatiquement sur [search].
  Stream<SearchEvent> searchStream(String query) async* {
    final agg = _Aggregator();
    final Stream<SseFrame> frames;
    try {
      frames = transport.connect(_uri('/search/stream', {'q': query}));
    } on UnsupportedError {
      // Repli : une seule salve, mais le même résultat.
      yield SearchSongs(await search(query));
      yield const SearchDone();
      return;
    }

    await for (final frame in frames) {
      final data = _decode(frame.data);
      if (data == null) continue;
      switch (frame.event) {
        case SseEvents.result:
          if (agg.addResult(data)) yield SearchSongs(agg.songs);
        case SseEvents.source:
          yield SearchSourceDone(SourceProgress(
            source: data['source'] as String? ?? '?',
            count: (data['count'] as num?)?.toInt() ?? 0,
            ms: (data['ms'] as num?)?.toInt() ?? 0,
            error: data['error'] as String?,
          ));
        case SseEvents.done:
          yield const SearchDone();
      }
    }
  }

  /// Recherche batch (un seul aller-retour). Lève en cas d'erreur réseau/HTTP.
  Future<List<RemoteSong>> search(String query) async {
    final resp = await http
        .get(_uri('/search', {'q': query}))
        .timeout(const Duration(seconds: 40));
    if (resp.statusCode != 200) {
      throw Exception('Recherche indisponible (HTTP ${resp.statusCode})');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is! Map) return const [];

    final agg = _Aggregator();
    for (final entry in _lists.entries) {
      final items = data[entry.key];
      if (items is! List) continue;
      for (final item in items.whereType<Map>()) {
        agg.add(
          type: entry.value,
          title: item['title'] as String? ?? '',
          artist: item['artist'] as String? ?? '',
          source: item['source'] as String? ?? '',
          content: item['content'] as String? ?? '',
        );
      }
    }
    return agg.songs;
  }

  static Map<String, dynamic>? _decode(String data) {
    try {
      final json = jsonDecode(data);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null; // trame illisible : ignorée, le flux continue
    }
  }

  /// Slug ASCII simple, aussi utilisé comme identifiant local du morceau ajouté
  /// à la bibliothèque perso (doit rester stable d'une recherche à l'autre).
  static String slug(String text) {
    const from = 'àáâãäåāèéêëēìíîïīòóôõöøōùúûüūçñß';
    const to = 'aaaaaaaeeeeeiiiiiooooooouuuuucns';
    var s = text.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9\s-]'), '');
    s = s.replaceAll(RegExp(r'[\s_-]+'), '-');
    s = s.replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'untitled' : s;
  }
}

/// Regroupe les résultats par morceau (titre + artiste), au fil de leur arrivée.
///
/// Le backend renvoie une liste **par nature** (grilles, paroles, mélodies) ;
/// l'app, elle, affiche un morceau avec ses représentations. La première source
/// d'un type gagne : le backend a déjà dédoublonné et priorisé.
class _Aggregator {
  final Map<String, RemoteSong> _byKey = {};

  List<RemoteSong> get songs => List.unmodifiable(_byKey.values);

  /// Ajoute un résultat du flux (`{type,title,artist,source,content}`).
  /// Retourne `false` si le résultat était inexploitable ou déjà connu.
  bool addResult(Map<String, dynamic> data) {
    final type = RemoteCatalogService._types[data['type']];
    if (type == null) return false;
    return add(
      type: type,
      title: data['title'] as String? ?? '',
      artist: data['artist'] as String? ?? '',
      source: data['source'] as String? ?? '',
      content: data['content'] as String? ?? '',
    );
  }

  bool add({
    required RepresentationType type,
    required String title,
    required String artist,
    required String source,
    required String content,
  }) {
    title = title.trim();
    artist = artist.trim();
    if (title.isEmpty || content.isEmpty) return false;

    final key = '${RemoteCatalogService.slug(title)}|${RemoteCatalogService.slug(artist)}';
    final existing = _byKey[key];
    if (existing != null && existing.has(type)) return false;

    final contents = <RepresentationType, RemoteContent>{
      ...?existing?.contents,
      type: RemoteContent(source: source, content: content),
    };
    _byKey[key] = RemoteSong(
      id: [
        RemoteCatalogService.slug(title),
        if (artist.isNotEmpty) RemoteCatalogService.slug(artist),
      ].join('-'),
      title: existing?.title ?? title,
      artist: existing?.artist ?? (artist.isEmpty ? null : artist),
      contents: Map.unmodifiable(contents),
    );
    return true;
  }
}
