/// Petite base de données locale clé → valeur (JSON en texte), utilisée pour
/// **éviter de redemander au backend** ce qu'on a déjà (cf. [SearchCache]).
///
/// C'est volontairement minimal : pas de moteur de requêtes, pas de schéma, pas
/// de dépendance (ni sqflite ni hive). Un dossier de fichiers d'un côté, du
/// `localStorage` de l'autre — comme [UserLibraryStore] et [LyricsStore], avec
/// lesquels elle cohabite sans se marcher dessus (préfixe `rubato_db_` /
/// `rubato.db.`).
///
/// Implémentation dépendante de la plateforme (import conditionnel) :
///  - natif : fichiers `<documents>/rubato_db/<clé>.json` ;
///  - web : `localStorage`, clés `rubato.db.<clé>`.
///
/// API commune :
///
/// ```dart
/// Future<String?>      read(String key)
/// Future<bool>         write(String key, String value)
/// Future<bool>         delete(String key)
/// Future<List<String>> keys()
/// ```
library;

export 'local_db_stub.dart'
    if (dart.library.io) 'local_db_io.dart'
    if (dart.library.html) 'local_db_web.dart';
