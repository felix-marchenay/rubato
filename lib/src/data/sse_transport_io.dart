import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sse.dart';

/// Transport SSE natif (Android, desktop) : une requête GET dont on lit le corps
/// **au fur et à mesure**.
///
/// `http.Client.send` (et non `http.get`) est la clé : il rend une
/// `StreamedResponse`, donc les octets arrivent pendant que le backend écrit,
/// au lieu d'être bufferisés jusqu'à la fin.
class SseTransport implements SseChannel {
  const SseTransport();

  @override
  Stream<SseFrame> connect(Uri uri) {
    late StreamController<SseFrame> controller;
    http.Client? client;
    StreamSubscription<SseFrame>? sub;

    Future<void> close() async {
      await sub?.cancel();
      sub = null;
      client?.close(); // coupe la connexion HTTP
      client = null;
    }

    Future<void> start() async {
      client = http.Client();
      try {
        final request = http.Request('GET', uri)
          ..headers['Accept'] = 'text/event-stream'
          ..headers['Cache-Control'] = 'no-cache';
        final response = await client!.send(request);

        if (response.statusCode != 200) {
          controller.addError(
              Exception('Recherche indisponible (HTTP ${response.statusCode})'));
          await controller.close();
          await close();
          return;
        }

        sub = decodeSse(response.stream.transform(utf8.decoder)).listen(
          controller.add,
          onError: controller.addError,
          onDone: () async {
            await controller.close();
            await close();
          },
          cancelOnError: true,
        );
      } catch (e) {
        controller.addError(e);
        await controller.close();
        await close();
      }
    }

    controller = StreamController<SseFrame>(
      onListen: start,
      onCancel: close, // l'appelant s'arrête (trame done, écran quitté) → on ferme
    );
    return controller.stream;
  }
}
