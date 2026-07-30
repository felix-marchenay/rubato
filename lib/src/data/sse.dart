// Server-Sent Events : le format dans lequel le backend Go diffuse les
// résultats de recherche au compte-gouttes (`GET /search/stream`).
//
// Ce fichier ne contient que la partie **indépendante de la plateforme** : les
// noms d'événements et le décodeur de trames. Le transport, lui, diffère
// (`sse_transport.dart`) : `EventSource` natif sur le web, réponse HTTP lue en
// flux sur mobile/desktop.

/// Noms des événements émis par le backend (cf. backend/stream_handler.go).
class SseEvents {
  /// Un résultat de plus (grille, paroles ou mélodie).
  static const result = 'result';

  /// Une source vient de finir : compteur, durée, erreur éventuelle.
  static const source = 'source';

  /// Fin du flux — le client doit fermer la connexion.
  static const done = 'done';

  /// Tous les noms, pour les transports qui doivent s'abonner un par un
  /// (`EventSource.addEventListener`).
  static const all = [result, source, done];
}

/// Canal SSE : ce que sait faire un transport, quelle que soit la plateforme.
///
/// Implémenté par `SseTransport` (`EventSource` sur le web, réponse HTTP lue en
/// flux sur natif, et un repli qui lève). L'interface permet aussi d'injecter un
/// faux flux dans les tests, sans réseau.
abstract interface class SseChannel {
  /// Ouvre le flux. Annuler l'abonnement doit fermer la connexion.
  Stream<SseFrame> connect(Uri uri);
}

/// Une trame SSE décodée : le nom de l'événement et sa charge utile (du JSON,
/// dans notre cas).
class SseFrame {
  final String event;
  final String data;
  const SseFrame(this.event, this.data);
}

/// Décode un flux de texte SSE en trames.
///
/// Le protocole : des blocs séparés par une ligne vide, chaque bloc fait de
/// lignes `champ: valeur`. On n'exploite que `event:` et `data:`. Les morceaux
/// arrivent découpés n'importe où (c'est un flux TCP) → on accumule dans un
/// tampon et on ne rend une trame que quand son bloc est complet.
Stream<SseFrame> decodeSse(Stream<String> chunks) async* {
  var buffer = '';
  await for (final chunk in chunks) {
    buffer += chunk.replaceAll('\r\n', '\n');
    while (true) {
      final end = buffer.indexOf('\n\n');
      if (end < 0) break;
      final frame = parseSseBlock(buffer.substring(0, end));
      buffer = buffer.substring(end + 2);
      if (frame != null) yield frame;
    }
  }
}

/// Parse un bloc SSE (sans la ligne vide finale). `null` si le bloc n'a pas
/// d'événement nommé — commentaires « : ping », trames inconnues.
SseFrame? parseSseBlock(String block) {
  String? event;
  final data = StringBuffer();
  for (final line in block.split('\n')) {
    if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      // Plusieurs lignes `data:` se concatènent (le backend n'en émet qu'une,
      // mais autant respecter le protocole).
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trim());
    }
  }
  if (event == null || event.isEmpty) return null;
  return SseFrame(event, data.toString());
}
