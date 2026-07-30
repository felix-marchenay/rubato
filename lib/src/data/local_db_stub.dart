import 'key_value_store.dart';

/// Repli (plateformes sans fichiers ni navigateur) : aucun stockage. Le cache de
/// recherche se comporte alors comme s'il était toujours vide.
class LocalDb implements KeyValueStore {
  const LocalDb();

  @override
  Future<String?> read(String key) async => null;
  @override
  Future<bool> write(String key, String value) async => false;
  @override
  Future<bool> delete(String key) async => false;
  @override
  Future<List<String>> keys() async => const [];
}
