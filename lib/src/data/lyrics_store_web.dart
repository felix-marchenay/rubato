import 'dart:html' as html;

/// Stockage local pour le web : le navigateur n'a pas de système de fichiers,
/// on conserve donc les paroles dans `localStorage` (persiste entre les visites).
class LyricsStore {
  const LyricsStore();

  String _key(String songId) => 'rubato.lyrics.$songId';

  Future<String?> read(String songId) async {
    try {
      return html.window.localStorage[_key(songId)];
    } catch (_) {
      return null;
    }
  }

  Future<bool> save(String songId, String chordPro) async {
    try {
      html.window.localStorage[_key(songId)] = chordPro;
      return true;
    } catch (_) {
      return false;
    }
  }
}
