/// Contrat du stockage local clé → valeur, implémenté par `LocalDb` (une
/// version par plateforme, cf. [local_db.dart]).
///
/// Cette interface existe pour deux raisons : dire noir sur blanc ce que les
/// trois implémentations doivent respecter, et permettre d'injecter un faux
/// stockage dans les tests (les vraies implémentations dépendent du système de
/// fichiers ou du navigateur).
abstract interface class KeyValueStore {
  /// Valeur associée à la clé, ou `null` si absente/illisible.
  Future<String?> read(String key);

  /// Écrit la valeur. `false` si le stockage est indisponible ou plein — un
  /// échec d'écriture ne doit jamais casser la fonctionnalité appelante.
  Future<bool> write(String key, String value);

  /// Supprime la clé (succès même si elle n'existait pas).
  Future<bool> delete(String key);

  /// Toutes les clés connues du stockage.
  Future<List<String>> keys();
}
