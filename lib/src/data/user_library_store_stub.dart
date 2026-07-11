/// Repli (plateformes sans fichiers ni navigateur) : aucun stockage.
class UserLibraryStore {
  const UserLibraryStore();

  Future<String?> read(String songId, String type) async => null;
  Future<bool> write(String songId, String type, String content) async => false;
  Future<String?> readIndex() async => null;
  Future<bool> writeIndex(String json) async => false;
}
