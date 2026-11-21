import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'chord_detector.dart';
import 'chord_vocabulary.dart';
import 'mic_input.dart';

enum MicStatus { idle, starting, listening, denied, failed }

/// Micro + détecteur d'accords, avec le cycle de vie qui va autour :
/// autorisation, écran gardé allumé pendant l'écoute, coupure quand l'appli
/// passe en arrière-plan et reprise au retour.
class ListeningController extends ChangeNotifier with WidgetsBindingObserver {
  ListeningController({
    ChordVocabulary vocabulary = ChordVocabulary.standard,
    this.onFrame,
  }) {
    detector = ChordDetector(sampleRate: _mic.sampleRate, vocabulary: vocabulary);
    WidgetsBinding.instance.addObserver(this);
  }

  final _mic = MicInput();
  late final ChordDetector detector;

  /// Appelé pour chaque trame d'analyse, avant la mise à jour de [frame].
  final void Function(ListeningFrame frame)? onFrame;

  /// Dernière trame, pour l'affichage.
  final frame = ValueNotifier<ListeningFrame?>(null);

  MicStatus _status = MicStatus.idle;
  String? _error;
  StreamSubscription<Float32List>? _subscription;
  bool _resumeOnForeground = false;
  bool _disposed = false;

  MicStatus get status => _status;
  String? get error => _error;
  bool get isListening => _status == MicStatus.listening;

  void _setStatus(MicStatus status, [String? error]) {
    if (_disposed) return;
    _status = status;
    _error = error;
    notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || _status == MicStatus.starting || isListening) return;
    _setStatus(MicStatus.starting);
    try {
      if (!await _mic.requestPermission()) {
        _setStatus(MicStatus.denied);
        return;
      }
      final stream = await _mic.start();
      if (_disposed) {
        await _mic.stop();
        return;
      }
      detector.reset();
      _subscription = stream.listen(_onSamples, onError: _onError);
      WakelockPlus.enable();
      _setStatus(MicStatus.listening);
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    WakelockPlus.disable();
    await _mic.stop();
    _setStatus(MicStatus.idle);
  }

  Future<void> toggle() => isListening ? stop() : start();

  void _onError(Object e) {
    _subscription?.cancel();
    _subscription = null;
    WakelockPlus.disable();
    _setStatus(MicStatus.failed, '$e');
  }

  void _onSamples(Float32List samples) {
    final frames = detector.add(samples);
    if (frames.isEmpty) return;
    for (final f in frames) {
      onFrame?.call(f);
    }
    frame.value = frames.last;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (isListening) {
        _resumeOnForeground = true;
        stop();
      }
    } else if (state == AppLifecycleState.resumed && _resumeOnForeground) {
      _resumeOnForeground = false;
      start();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _mic.dispose();
    WakelockPlus.disable();
    frame.dispose();
    super.dispose();
  }
}
