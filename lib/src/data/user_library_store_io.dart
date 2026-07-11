import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Stockage local sur système de fichiers (Android, desktop).
/// Le dossier `lyrics/` + l'extension `.pro` coïncident avec [LyricsStore],
/// pour que les deux stores partagent les mêmes fichiers de paroles.
class UserLibraryStore {
  const UserLibraryStore();

  // type -> (sous-dossier, extension)
  static const _spec = {
    'chordGrid': ['charts', 'json'],
    'lyrics': ['lyrics', 'pro'],
    'score': ['scores', 'abc'],
  };

  Future<File?> _file(String songId, String type) async {
    final spec = _spec[type];
    if (spec == null) return null;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/${spec[0]}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$songId.${spec[1]}');
  }

  Future<String?> read(String songId, String type) async {
    try {
      final f = await _file(songId, type);
      if (f != null && await f.exists()) return await f.readAsString();
    } catch (_) {
      // Stockage indisponible : rien en local.
    }
    return null;
  }

  Future<bool> write(String songId, String type, String content) async {
    try {
      final f = await _file(songId, type);
      if (f == null) return false;
      await f.writeAsString(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<File> _indexFile() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/rubato_userlibrary.json');
  }

  Future<String?> readIndex() async {
    try {
      final f = await _indexFile();
      if (await f.exists()) return await f.readAsString();
    } catch (_) {}
    return null;
  }

  Future<bool> writeIndex(String json) async {
    try {
      await (await _indexFile()).writeAsString(json);
      return true;
    } catch (_) {
      return false;
    }
  }
}
