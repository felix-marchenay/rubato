/// Stockage local des paroles récupérées, pour les conserver hors-ligne.
///
/// L'implémentation dépend de la plateforme (import conditionnel) :
///  - natif (Android…) : un vrai fichier `<documents>/lyrics/<id>.pro` ;
///  - web : `localStorage` (pas de système de fichiers dans le navigateur).
///
/// API commune :
///   Future<String?> read(String songId)              // texte ChordPro ou null
///   Future<bool>    save(String songId, String pro)   // true si conservé
export 'lyrics_store_stub.dart'
    if (dart.library.io) 'lyrics_store_io.dart'
    if (dart.library.html) 'lyrics_store_web.dart';
