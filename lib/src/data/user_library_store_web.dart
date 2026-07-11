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
