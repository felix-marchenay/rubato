/// Repli pour les plateformes sans système de fichiers ni navigateur :
/// aucun stockage, la récupération reste possible mais non conservée.
class LyricsStore {
  const LyricsStore();

  Future<String?> read(String songId) async => null;

  Future<bool> save(String songId, String chordPro) async => false;
}
