import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_update_service.dart';
import '../theme.dart';

/// Bandeau « Nouvelle version disponible » : vérifie au lancement, puis
/// télécharge et ouvre l'installeur d'Android à la demande. Invisible quand
/// l'appli est à jour (et toujours sur le web).
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  final _service = AppUpdateService();
  AppRelease? _release;
  UpdateProgress? _progress;
  StreamSubscription<UpdateProgress>? _subscription;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (!AppUpdateService.isSupported) return;
    _service.check().then((release) {
      if (mounted && release != null) setState(() => _release = release);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _install() {
    _subscription?.cancel();
    setState(() => _progress = const UpdateDownloading(null));
    _subscription = _service.install(_release!).listen((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    if (release == null || _dismissed) return const SizedBox.shrink();
    final p = context.palette;
    final text = TextStyle(color: p.onBrassTint, fontSize: 13, height: 1.35);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(
        color: p.brassTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.system_update, size: 20, color: p.onBrassTint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nouvelle version de Rubato',
                  style: RubatoType.serif(size: 16, color: p.onBrassTint),
                ),
              ),
            ],
          ),
          if (release.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4, right: 8),
              child: Text(
                release.notes,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 6),
            child: _status(text),
          ),
        ],
      ),
    );
  }

  Widget _status(TextStyle text) {
    final p = context.palette;
    switch (_progress) {
      case null:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _dismissed = true),
              child: Text('Plus tard', style: TextStyle(color: p.onBrassTint)),
            ),
            const SizedBox(width: 4),
            FilledButton(onPressed: _install, child: const Text('Installer')),
          ],
        );
      case UpdateDownloading(:final fraction):
        return Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 10, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: fraction,
                backgroundColor: p.line,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 6),
              Text(
                fraction == null
                    ? 'Téléchargement…'
                    : 'Téléchargement… ${(fraction * 100).round()} %',
                style: text,
              ),
            ],
          ),
        );
      case UpdateInstallerOpened():
        return _messageWithAction(
          'Confirme l\'installation dans l\'écran d\'Android.',
          'Relancer',
          text,
        );
      case UpdateFailed(:final message):
        return _messageWithAction(message, 'Réessayer', text);
    }
  }

  Widget _messageWithAction(String message, String action, TextStyle text) {
    return Row(
      children: [
        Expanded(child: Text(message, style: text)),
        TextButton(onPressed: _install, child: Text(action)),
      ],
    );
  }
}
