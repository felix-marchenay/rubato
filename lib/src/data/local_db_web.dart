// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
//
// Les deux lints sont attendus ici et n'ont pas de correctif possible dans ce
// fichier : `dart:html` est « web-only » et déprécié, mais ce fichier n'est
// compilé QUE pour le web (import conditionnel `if (dart.library.html)` dans
// local_db.dart) — le motif que ces lints ne savent pas distinguer. La migration vers
// `package:web` + `dart:js_interop` reste à faire ; garder `dart.library.html`
// comme garde tant que l'import est `dart:html`, sinon un build Wasm choisirait
// ce fichier et ne compilerait pas.

import 'dart:html' as html;

import 'key_value_store.dart';

/// Base locale pour le web : `localStorage`, une entrée par clé, préfixée
/// `rubato.db.` pour ne pas se mélanger avec les paroles (`rubato.lyrics.<id>`)
/// ni la bibliothèque (`rubato.userlibrary`).
class LocalDb implements KeyValueStore {
  const LocalDb();

  static const _prefix = 'rubato.db.';

  @override
  Future<String?> read(String key) async {
    try {
      return html.window.localStorage['$_prefix$key'];
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> write(String key, String value) async {
    try {
      html.window.localStorage['$_prefix$key'] = value;
      return true;
    } catch (_) {
      // Quota dépassé (localStorage ≈ 5 Mo) : le cache n'est qu'une commodité,
      // on n'échoue pas la recherche pour autant.
      return false;
    }
  }

  @override
  Future<bool> delete(String key) async {
    try {
      html.window.localStorage.remove('$_prefix$key');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> keys() async {
    try {
      return html.window.localStorage.keys
          .where((k) => k.startsWith(_prefix))
          .map((k) => k.substring(_prefix.length))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
