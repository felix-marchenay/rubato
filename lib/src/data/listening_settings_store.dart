import 'dart:convert';

import '../audio/chord_vocabulary.dart';
import 'key_value_store.dart';
import 'local_db.dart';

/// Réglages de l'écoute, communs à l'écran Écouter et au mode entraînement.
class ListeningSettings {
  /// Seuil de niveau (dBFS) : en dessous, pas de son.
  final double gateDb;

  /// Combien de temps (s) une note jouée continue de compter.
  final double remanenceSeconds;

  /// Accords cherchés sur l'écran Écouter (l'entraînement n'en dépend pas).
  final ChordVocabulary vocabulary;

  const ListeningSettings({
    this.gateDb = -55,
    this.remanenceSeconds = 1.2,
    this.vocabulary = ChordVocabulary.standard,
  });

  ListeningSettings copyWith({
    double? gateDb,
    double? remanenceSeconds,
    ChordVocabulary? vocabulary,
  }) =>
      ListeningSettings(
        gateDb: gateDb ?? this.gateDb,
        remanenceSeconds: remanenceSeconds ?? this.remanenceSeconds,
        vocabulary: vocabulary ?? this.vocabulary,
      );

  Map<String, Object> toJson() => {
        'gateDb': gateDb,
        'remanenceSeconds': remanenceSeconds,
        'vocabulary': vocabulary.name,
      };

  /// Tolérant : une valeur absente ou illisible garde sa valeur par défaut.
  factory ListeningSettings.fromJson(Map<String, dynamic> json) {
    const d = ListeningSettings();
    final gate = json['gateDb'];
    final remanence = json['remanenceSeconds'];
    return ListeningSettings(
      gateDb: gate is num ? gate.toDouble() : d.gateDb,
      remanenceSeconds:
          remanence is num && remanence > 0 ? remanence.toDouble() : d.remanenceSeconds,
      vocabulary: ChordVocabulary.values.firstWhere(
        (v) => v.name == json['vocabulary'],
        orElse: () => d.vocabulary,
      ),
    );
  }
}

/// Garde les réglages d'écoute d'une session à l'autre.
class ListeningSettingsStore {
  const ListeningSettingsStore({this.db = const LocalDb()});

  final KeyValueStore db;

  static const _key = 'listening.settings';

  Future<ListeningSettings> read() async {
    try {
      final raw = await db.read(_key);
      if (raw == null) return const ListeningSettings();
      return ListeningSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ListeningSettings();
    }
  }

  Future<void> write(ListeningSettings settings) =>
      db.write(_key, jsonEncode(settings.toJson()));
}
