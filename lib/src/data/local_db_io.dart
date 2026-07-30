import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'key_value_store.dart';

/// Base locale sur système de fichiers (Android, desktop) : un fichier `.json`
/// par clé dans `<documents>/rubato_db/`.
class LocalDb implements KeyValueStore {
  const LocalDb();

  static const _dirName = 'rubato_db';

  /// Les clés viennent de requêtes utilisateur → tout ce qui n'est pas
  /// alphanumérique est remplacé, pour ne jamais fabriquer de chemin douteux
  /// (« ../ », séparateurs, caractères interdits selon le système).
  static String _safe(String key) {
    final cleaned = key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? '_' : cleaned;
  }

  Future<Directory?> _dir({bool create = false}) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/$_dirName');
      if (create && !await dir.exists()) {
        await dir.create(recursive: true);
      }
      return await dir.exists() ? dir : null;
    } catch (_) {
      return null; // stockage indisponible
    }
  }

  @override
  Future<String?> read(String key) async {
    try {
      final dir = await _dir();
      if (dir == null) return null;
      final f = File('${dir.path}/${_safe(key)}.json');
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return null;
  }

  @override
  Future<bool> write(String key, String value) async {
    try {
      final dir = await _dir(create: true);
      if (dir == null) return false;
      await File('${dir.path}/${_safe(key)}.json').writeAsString(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> delete(String key) async {
    try {
      final dir = await _dir();
      if (dir == null) return false;
      final f = File('${dir.path}/${_safe(key)}.json');
      if (await f.exists()) await f.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> keys() async {
    try {
      final dir = await _dir();
      if (dir == null) return const [];
      return dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.json'))
          .map((n) => n.substring(0, n.length - 5))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
