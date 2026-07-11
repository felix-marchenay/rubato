import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Stockage local sur système de fichiers (Android, desktop) : un fichier
/// `<documents applicatifs>/lyrics/<id>.pro` par morceau.
class LyricsStore {
  const LyricsStore();

  Future<File> _file(String songId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/lyrics');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$songId.pro');
  }

  Future<String?> read(String songId) async {
    try {
      final f = await _file(songId);
      if (await f.exists()) return await f.readAsString();
    } catch (_) {
      // Stockage indisponible : on considère qu'il n'y a rien en local.
    }
    return null;
  }

  Future<bool> save(String songId, String chordPro) async {
    try {
      final f = await _file(songId);
      await f.writeAsString(chordPro);
      return true;
    } catch (_) {
      return false;
    }
  }
}
