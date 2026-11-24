import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mscore/src/data/app_update_service.dart';

const _latest = {
  'version': '1.0.0',
  'build': 1540000,
  'url': 'https://github.com/o/r/releases/download/android-latest/rubato-1.0.0-1540000.apk',
  'sha256': 'abc123',
  'notes': 'Écoute : meilleure détection des 7e',
  'publishedAt': '2026-11-21T15:00:00+00:00',
};

AppUpdateService _service(
  http.Client client, {
  int installed = 1530000,
}) =>
    AppUpdateService(
      client: client,
      manifestUrl: Uri.parse('https://example.test/latest.json'),
      installedBuild: () async => installed,
    );

MockClient _serving(Object body, {int status = 200}) => MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(body is String ? body : jsonEncode(body)),
        status,
      ),
    );

void main() {
  test('latest.json est lu tel que le publie make release', () {
    final r = AppRelease.fromJson(_latest);
    expect(r.version, '1.0.0');
    expect(r.build, 1540000);
    expect(r.apkUrl.path, endsWith('rubato-1.0.0-1540000.apk'));
    expect(r.sha256, 'abc123');
    expect(r.notes, 'Écoute : meilleure détection des 7e');
  });

  test('propose la version publiée si elle est plus récente', () async {
    final r = await _service(_serving(_latest)).check();
    expect(r?.build, 1540000);
  });

  test('rien à proposer si l\'appli est à jour ou plus récente', () async {
    expect(await _service(_serving(_latest), installed: 1540000).check(), isNull);
    expect(await _service(_serving(_latest), installed: 1600000).check(), isNull);
  });

  test('une vérification ratée reste silencieuse', () async {
    expect(await _service(_serving('Not Found', status: 404)).check(), isNull);
    expect(await _service(_serving('<html>oups</html>')).check(), isNull);
    expect(await _service(_serving({'version': '1.0.0'})).check(), isNull);
    final offline = MockClient((_) async => throw http.ClientException('hors ligne'));
    expect(await _service(offline).check(), isNull);
  });
}
