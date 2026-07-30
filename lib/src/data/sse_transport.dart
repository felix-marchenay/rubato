/// Transport SSE dépendant de la plateforme (import conditionnel).
///
/// API commune :
///   Stream<SseFrame> SseTransport().connect(Uri uri)
///
/// Le flux se termine à la trame `done` (ou à la fermeture par le serveur), et
/// annuler l'abonnement coupe la connexion — indispensable : sur le web,
/// `EventSource` se **reconnecte tout seul** si on ne la ferme pas.
///
/// Sur une plateforme sans transport (stub), `connect` lève : l'appelant retombe
/// alors sur la recherche batch (`/search`).
export 'sse_transport_stub.dart'
    if (dart.library.io) 'sse_transport_io.dart'
    if (dart.library.html) 'sse_transport_web.dart';
