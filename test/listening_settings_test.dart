import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/audio/chord_vocabulary.dart';
import 'package:mscore/src/data/key_value_store.dart';
import 'package:mscore/src/data/listening_settings_store.dart';

class _MemoryStore implements KeyValueStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<bool> write(String key, String value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async => data.remove(key) != null;
  @override
  Future<List<String>> keys() async => data.keys.toList();
}

void main() {
  test('les réglages sont gardés d\'une session à l\'autre', () async {
    final db = _MemoryStore();
    final store = ListeningSettingsStore(db: db);
    expect((await store.read()).remanenceSeconds, 1.2, reason: 'défaut');

    await store.write(const ListeningSettings(
      gateDb: -62,
      remanenceSeconds: 0.4,
      vocabulary: ChordVocabulary.jazz,
    ));
    final again = await ListeningSettingsStore(db: db).read();
    expect(again.gateDb, -62);
    expect(again.remanenceSeconds, 0.4);
    expect(again.vocabulary, ChordVocabulary.jazz);
  });

  test('une sauvegarde abîmée ou d\'une ancienne version retombe sur les défauts',
      () async {
    final db = _MemoryStore()..data['listening.settings'] = '{oups';
    expect((await ListeningSettingsStore(db: db).read()).gateDb, -55);

    final partial = ListeningSettings.fromJson({
      'gateDb': -60,
      'remanenceSeconds': -1,
      'vocabulary': 'inconnu',
    });
    expect(partial.gateDb, -60);
    expect(partial.remanenceSeconds, 1.2);
    expect(partial.vocabulary, ChordVocabulary.standard);
  });
}
