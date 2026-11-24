import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../audio/listening_controller.dart';
import '../theme.dart';

/// Niveau d'entrée (−80..−20 dBFS) avec un repère au seuil d'écoute.
class LevelMeter extends StatelessWidget {
  final double levelDb;
  final double gateDb;

  const LevelMeter({super.key, required this.levelDb, required this.gateDb});

  static double _pos(double db) => ((db + 80) / 60).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CustomPaint(
      size: const Size.fromHeight(6),
      painter: _LevelPainter(
        level: _pos(levelDb),
        gate: _pos(gateDb),
        track: p.line,
        fill: levelDb >= gateDb ? p.brass : p.inkMuted,
        mark: p.ink,
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  final double level, gate;
  final Color track, fill, mark;

  _LevelPainter({
    required this.level,
    required this.gate,
    required this.track,
    required this.fill,
    required this.mark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width * level, size.height), r),
      Paint()..color = fill,
    );
    final x = size.width * gate;
    canvas.drawLine(
      Offset(x, -2),
      Offset(x, size.height + 2),
      Paint()
        ..color = mark
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_LevelPainter old) =>
      old.level != level || old.gate != gate || old.fill != fill;
}

class MicButton extends StatelessWidget {
  final MicStatus status;
  final VoidCallback onPressed;
  final double size;

  const MicButton({
    super.key,
    required this.status,
    required this.onPressed,
    this.size = 72,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final listening = status == MicStatus.listening;
    final starting = status == MicStatus.starting;
    return Semantics(
      button: true,
      label: listening ? 'Arrêter l\'écoute' : 'Écouter',
      child: GestureDetector(
        onTap: starting ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: listening ? p.brass : p.surface,
            border: Border.all(color: p.brass, width: 1.5),
          ),
          child: starting
              ? Padding(
                  padding: EdgeInsets.all(size / 3),
                  child: CircularProgressIndicator(strokeWidth: 2, color: p.brass),
                )
              : Icon(
                  listening ? Icons.mic : Icons.mic_none,
                  size: size * 0.44,
                  color: listening ? p.onBrass : p.brass,
                ),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  final String title;
  final String detail;
  final VoidCallback onRetry;

  const _Problem({
    required this.title,
    required this.detail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off, size: 40, color: p.inkMuted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: RubatoType.serif(size: 18, color: p.ink),
            ),
            const SizedBox(height: 12),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 24),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}


/// Message plein écran quand le micro est refusé ou indisponible.
class MicProblem extends StatelessWidget {
  final ListeningController controller;

  const MicProblem({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final denied = controller.status == MicStatus.denied;
    return _Problem(
      title: denied
          ? 'Rubato a besoin du micro pour reconnaître les accords.'
          : 'Impossible d\'ouvrir le micro.',
      detail: denied
          ? (kIsWeb
              ? 'Autorise-le depuis la barre d\'adresse du navigateur, '
                  'puis réessaie.'
              : 'Autorise-le dans les réglages du téléphone '
                  '(Applications › Rubato › Autorisations), puis réessaie.')
          : [
              if (kIsWeb)
                'Sur le web, le micro n\'est accessible qu\'en https ou sur '
                    'localhost.',
              ?controller.error,
            ].join('\n\n'),
      onRetry: controller.start,
    );
  }
}
