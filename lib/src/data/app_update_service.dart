import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Version de l'appli Android publiée par `make release` (latest.json).
class AppRelease {
  final String version;
  final int build;
  final Uri apkUrl;
  final String sha256;
  final String notes;

  const AppRelease({
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.sha256,
    this.notes = '',
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        version: json['version'] as String,
        build: (json['build'] as num).toInt(),
        apkUrl: Uri.parse(json['url'] as String),
        sha256: json['sha256'] as String,
        notes: (json['notes'] as String?) ?? '',
      );

  bool isNewerThan(int installedBuild) => build > installedBuild;
}

/// Étape d'une installation de mise à jour.
sealed class UpdateProgress {
  const UpdateProgress();
}

class UpdateDownloading extends UpdateProgress {
  /// 0..1, null tant que la taille est inconnue.
  final double? fraction;
  const UpdateDownloading(this.fraction);
}

/// L'écran d'installation d'Android est ouvert : la suite est entre les mains
/// de l'utilisateur.
class UpdateInstallerOpened extends UpdateProgress {
  const UpdateInstallerOpened();
}

class UpdateFailed extends UpdateProgress {
  final String message;
  const UpdateFailed(this.message);
}

/// Mise à jour de l'appli Android hors Play Store : l'appli lit latest.json
/// sur la release GitHub `android-latest`, télécharge l'APK puis ouvre
/// l'installeur d'Android (qui demande toujours une confirmation).
class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    Uri? manifestUrl,
    Future<int> Function()? installedBuild,
  })  : _client = client ?? http.Client(),
        _manifestUrl = manifestUrl ?? defaultManifestUrl,
        _installedBuild = installedBuild ?? _packageBuild;

  static final defaultManifestUrl = Uri.parse(const String.fromEnvironment(
    'RUBATO_UPDATE_URL',
    defaultValue: 'https://github.com/felix-marchenay/rubato/releases/'
        'download/android-latest/latest.json',
  ));

  /// Seule l'appli Android s'installe ainsi ; le web se met à jour en
  /// rechargeant la page.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final http.Client _client;
  final Uri _manifestUrl;
  final Future<int> Function() _installedBuild;

  static Future<int> _packageBuild() async =>
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  /// La mise à jour disponible, ou null : déjà à jour, hors ligne, rien de
  /// publié… Une vérification ratée ne doit jamais gêner l'utilisateur.
  Future<AppRelease?> check() async {
    try {
      final resp = await _client
          .get(_manifestUrl, headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(resp.bodyBytes));
      if (json is! Map<String, dynamic>) return null;
      final release = AppRelease.fromJson(json);
      return release.isNewerThan(await _installedBuild()) ? release : null;
    } catch (_) {
      return null;
    }
  }

  /// Télécharge l'APK (empreinte vérifiée) puis ouvre l'installeur d'Android.
  Stream<UpdateProgress> install(AppRelease release) async* {
    try {
      await for (final event in OtaUpdate().execute(
        release.apkUrl.toString(),
        destinationFilename: 'rubato-${release.build}.apk',
        sha256checksum: release.sha256,
      )) {
        yield _toProgress(event);
      }
    } catch (e) {
      yield UpdateFailed('Installation impossible ($e).');
    }
  }

  static UpdateProgress _toProgress(OtaEvent e) => switch (e.status) {
        OtaStatus.DOWNLOADING =>
          UpdateDownloading(_percent(e.value)),
        OtaStatus.INSTALLING ||
        OtaStatus.INSTALLATION_DONE =>
          const UpdateInstallerOpened(),
        OtaStatus.PERMISSION_NOT_GRANTED_ERROR => const UpdateFailed(
            'Android n\'autorise pas encore Rubato à installer des applis : '
            'Réglages › Applis › Rubato › Installer des applis inconnues.'),
        OtaStatus.CHECKSUM_ERROR => const UpdateFailed(
            'Le fichier téléchargé est corrompu. Réessaie.'),
        OtaStatus.DOWNLOAD_ERROR => const UpdateFailed(
            'Téléchargement impossible. Vérifie la connexion et réessaie.'),
        OtaStatus.ALREADY_RUNNING_ERROR => const UpdateFailed(
            'Un téléchargement est déjà en cours.'),
        OtaStatus.CANCELED => const UpdateFailed('Téléchargement annulé.'),
        OtaStatus.INSTALLATION_ERROR ||
        OtaStatus.INTERNAL_ERROR =>
          UpdateFailed('Installation impossible (${e.value ?? 'erreur'}).'),
      };

  static double? _percent(String? value) {
    final p = double.tryParse(value ?? '');
    return p == null ? null : (p / 100).clamp(0.0, 1.0);
  }
}
