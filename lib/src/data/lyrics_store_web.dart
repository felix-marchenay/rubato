// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
//
// Les deux lints sont attendus ici et n'ont pas de correctif possible dans ce
// fichier : `dart:html` est « web-only » et déprécié, mais ce fichier n'est
// compilé QUE pour le web (import conditionnel `if (dart.library.html)` dans
// lyrics_store.dart) — le motif que ces lints ne savent pas distinguer. La migration vers
// `package:web` + `dart:js_interop` reste à faire ; garder `dart.library.html`
// comme garde tant que l'import est `dart:html`, sinon un build Wasm choisirait
// ce fichier et ne compilerait pas.

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
