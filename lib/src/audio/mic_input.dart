import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';

import 'pcm.dart';

/// Micro → flux d'échantillons mono (−1..1), via le paquet `record`.
class MicInput {
  /// 48 kHz sur le web : fréquence native de la plupart des cartes son, donc
  /// pas de rééchantillonnage. 44,1 kHz sur Android : la seule garantie
  /// partout.
  final int sampleRate = kIsWeb ? 48000 : 44100;

  final _recorder = AudioRecorder();

  /// Sources Android par ordre de préférence : brute si l'appareil la
  /// propose, sinon celle de la reconnaissance vocale (sans gain automatique
  /// sur la plupart des appareils), sinon celle par défaut.
  static const _androidSources = [
    AndroidAudioSource.unprocessed,
    AndroidAudioSource.voiceRecognition,
    AndroidAudioSource.defaultSource,
  ];

  /// Demande l'autorisation si besoin.
  Future<bool> requestPermission() => _recorder.hasPermission();

  Future<Stream<Float32List>> start() async {
    for (var i = 0;; i++) {
      try {
        final bytes = await _recorder.startStream(_config(_androidSources[i]));
        final decoder = Pcm16Decoder();
        return bytes.map(decoder.convert);
      } catch (_) {
        if (kIsWeb || i == _androidSources.length - 1) rethrow;
      }
    }
  }

  RecordConfig _config(AndroidAudioSource source) => RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        // Traitements pensés pour la voix au téléphone : ils écrasent la
        // dynamique et filtrent les harmoniques de la musique.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        // Petits paquets (~20 ms) : par défaut Android en envoie de 80 à
        // 170 ms, autant de retard avant la moindre analyse. Octets sur
        // Android, échantillons sur le web.
        streamBufferSize: kIsWeb ? 1024 : 2048,
        androidConfig: AndroidRecordConfig(audioSource: source),
      );

  Future<void> stop() => _recorder.stop();

  Future<void> dispose() => _recorder.dispose();
}
