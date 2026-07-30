import 'sse.dart';

/// Repli : pas de transport SSE sur cette plateforme. L'appelant attrape et
/// retombe sur la recherche batch (`/search`), qui donne le même résultat mais
/// d'un seul bloc.
class SseTransport implements SseChannel {
  const SseTransport();

  @override
  Stream<SseFrame> connect(Uri uri) =>
      throw UnsupportedError('SSE indisponible sur cette plateforme');
}
