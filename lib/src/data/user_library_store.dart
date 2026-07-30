/// Stockage local de la bibliothèque personnelle (représentations récupérées en
/// ligne + index des morceaux ajoutés). Généralise [LyricsStore] aux trois
/// types de représentation, et reste **interopérable** avec lui (mêmes
/// fichiers `.pro` / mêmes clés `rubato.lyrics.<id>`).
///
/// Implémentation dépendante de la plateforme (import conditionnel) :
///  - natif : fichiers `<documents>/{charts|lyrics|scores}/<id>.{json|pro|abc}`
///    + index `<documents>/rubato_userlibrary.json` ;
///  - web : `localStorage`, clés `rubato.{chart|lyrics|score}.<id>`
///    + index `rubato.userlibrary`.
///
/// API commune (type = 'chordGrid' | 'lyrics' | 'score') :
///
/// ```dart
/// Future<String?> read(String songId, String type)
/// Future<bool>    write(String songId, String type, String content)
/// Future<String?> readIndex()
/// Future<bool>    writeIndex(String json)
/// ```
library;

export 'user_library_store_stub.dart'
    if (dart.library.io) 'user_library_store_io.dart'
    if (dart.library.html) 'user_library_store_web.dart';
