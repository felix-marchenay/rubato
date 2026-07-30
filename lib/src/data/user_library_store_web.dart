// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
//
// Les deux lints sont attendus ici et n'ont pas de correctif possible dans ce
// fichier : `dart:html` est « web-only » et déprécié, mais ce fichier n'est
// compilé QUE pour le web (import conditionnel `if (dart.library.html)` dans
// user_library_store.dart) — le motif que ces lints ne savent pas distinguer. La migration vers
// `package:web` + `dart:js_interop` reste à faire ; garder `dart.library.html`
// comme garde tant que l'import est `dart:html`, sinon un build Wasm choisirait
// ce fichier et ne compilerait pas.

import 'dart:html' as html;

/// Stockage local pour le web (`localStorage`). La clé des paroles
/// (`rubato.lyrics.<id>`) coïncide avec [LyricsStore].
class UserLibraryStore {
  const UserLibraryStore();

  static const _keyByType = {
    'chordGrid': 'chart',
    'lyrics': 'lyrics',
    'score': 'score',
  };

  String? _key(String songId, String type) {
    final k = _keyByType[type];
    return k == null ? null : 'rubato.$k.$songId';
  }

  Future<String?> read(String songId, String type) async {
    try {
      final k = _key(songId, type);
      return k == null ? null : html.window.localStorage[k];
    } catch (_) {
      return null;
    }
  }

  Future<bool> write(String songId, String type, String content) async {
    try {
      final k = _key(songId, type);
      if (k == null) return false;
      html.window.localStorage[k] = content;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> readIndex() async {
    try {
      return html.window.localStorage['rubato.userlibrary'];
    } catch (_) {
      return null;
    }
  }

  Future<bool> writeIndex(String json) async {
    try {
      html.window.localStorage['rubato.userlibrary'] = json;
      return true;
    } catch (_) {
      return false;
    }
  }
}
