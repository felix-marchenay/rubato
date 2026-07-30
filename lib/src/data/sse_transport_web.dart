// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
//
// Les deux lints sont attendus ici et n'ont pas de correctif possible dans ce
// fichier : `dart:html` est « web-only » et déprécié, mais ce fichier n'est
// compilé QUE pour le web (import conditionnel `if (dart.library.html)` dans
// sse_transport.dart) — le motif que ces lints ne savent pas distinguer. La migration vers
// `package:web` + `dart:js_interop` reste à faire ; garder `dart.library.html`
// comme garde tant que l'import est `dart:html`, sinon un build Wasm choisirait
// ce fichier et ne compilerait pas.

import 'dart:async';
import 'dart:html' as html;

import 'sse.dart';

/// Transport SSE pour le web : `EventSource`, l'API navigateur faite pour ça.
///
/// C'est ce qui évite une dépendance : le client HTTP du web (XHR) rend la
/// réponse **complète** une fois terminée, donc il ne sait pas streamer, alors
/// qu'`EventSource` livre chaque événement à l'arrivée.
///
/// Deux pièges traités ici :
///  - `EventSource` **reconnecte automatiquement** quand le serveur ferme le
///    flux → il faut appeler `close()` (fait sur `done`, sur erreur, et quand
///    l'appelant annule son abonnement) sinon la recherche repart en boucle ;
///  - une erreur peut simplement signifier « le serveur a fini » : on ne la
///    remonte donc que si aucune trame `done` n'est passée.
class SseTransport implements SseChannel {
  const SseTransport();

  @override
  Stream<SseFrame> connect(Uri uri) {
    late StreamController<SseFrame> controller;
    html.EventSource? source;
    var finished = false;

    void close() {
      source?.close();
      source = null;
    }

    void start() {
      source = html.EventSource(uri.toString());

      for (final name in SseEvents.all) {
        source!.addEventListener(name, (event) {
          final data = (event as html.MessageEvent).data;
          controller.add(SseFrame(name, data is String ? data : '$data'));
          if (name == SseEvents.done) {
            finished = true;
            close();
            controller.close();
          }
        });
      }

      source!.onError.listen((_) {
        close();
        if (!finished) {
          controller.addError(Exception('Flux de recherche interrompu'));
        }
        controller.close();
      });
    }

    controller = StreamController<SseFrame>(onListen: start, onCancel: close);
    return controller.stream;
  }
}
