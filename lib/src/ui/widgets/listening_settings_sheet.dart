import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/chord_detector.dart';
import '../../audio/chord_vocabulary.dart';
import '../../audio/listening_controller.dart';
import '../theme.dart';
import 'listening_widgets.dart';
import 'pill_toggle.dart';

/// Réglages de l'écoute (sensibilité, rémanence, et accords cherchés sur
/// l'écran Écouter), appliqués à chaud et mémorisés.
Future<void> showListeningSettings(
  BuildContext context,
  ListeningController controller, {
  bool showVocabulary = true,
}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _ListeningSettingsSheet(
          controller: controller,
          showVocabulary: showVocabulary,
        ),
      ),
    );

class _ListeningSettingsSheet extends StatelessWidget {
  final ListeningController controller;
  final bool showVocabulary;

  const _ListeningSettingsSheet({
    required this.controller,
    required this.showVocabulary,
  });

  static const _vocabularyHelp = {
    ChordVocabulary.simple: 'Accords majeurs et mineurs.',
    ChordVocabulary.standard: 'Plus les 7e (7, maj7, m7), sus2, sus4 et dim.',
    ChordVocabulary.jazz: 'Plus 6, m6, ø, °7, aug et 7sus. Les confusions '
        'deviennent plus fréquentes (C6 et Am7 ont les mêmes notes).',
  };

  // Rémanence sur une échelle logarithmique : 0,15 s … 4 s.
  static const _minRemanence = 0.15;
  static const _maxRemanence = 4.0;

  static double _toSlider(double seconds) =>
      math.log(seconds.clamp(_minRemanence, _maxRemanence) / _minRemanence) /
      math.log(_maxRemanence / _minRemanence);

  static double _fromSlider(double v) =>
      _minRemanence * math.pow(_maxRemanence / _minRemanence, v);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = controller.settings;
    final help = TextStyle(color: p.inkMuted, fontSize: 13, height: 1.4);
    final seconds = s.remanenceSeconds.toStringAsFixed(1).replaceAll('.', ',');

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Réglages de l\'écoute',
                style: RubatoType.serif(size: 20, color: p.ink)),
            if (showVocabulary) ...[
              const SizedBox(height: 20),
              Text('ACCORDS RECHERCHÉS', style: RubatoType.caption(p.inkMuted)),
              const SizedBox(height: 10),
              PillToggle<ChordVocabulary>(
                value: s.vocabulary,
                options: {for (final v in ChordVocabulary.values) v: v.label},
                onChanged: (v) =>
                    controller.updateSettings(s.copyWith(vocabulary: v)),
              ),
              const SizedBox(height: 8),
              Text(_vocabularyHelp[s.vocabulary]!, style: help),
            ],
            const SizedBox(height: 24),
            Text('SENSIBILITÉ', style: RubatoType.caption(p.inkMuted)),
            Slider(
              min: 35,
              max: 75,
              value: (-s.gateDb).clamp(35, 75),
              onChanged: (v) => controller.updateSettings(s.copyWith(gateDb: -v)),
            ),
            ValueListenableBuilder<ListeningFrame?>(
              valueListenable: controller.frame,
              builder: (context, f, _) => Row(
                children: [
                  Expanded(
                    child: LevelMeter(
                      levelDb: f?.levelDb ?? -120,
                      gateDb: s.gateDb,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: Text(
                      (f?.hasSignal ?? false) ? 'son entendu' : 'sous le seuil',
                      style: TextStyle(color: p.inkMuted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Le trait marque le seuil : en dessous, rien n\'est analysé. '
              'Monte la sensibilité si l\'instrument est loin, baisse-la dans un '
              'lieu bruyant.',
              style: help,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('RÉMANENCE', style: RubatoType.caption(p.inkMuted)),
                const Spacer(),
                Text('$seconds s', style: RubatoType.caption(p.brass)),
              ],
            ),
            Slider(
              value: _toSlider(s.remanenceSeconds),
              onChanged: (v) => controller
                  .updateSettings(s.copyWith(remanenceSeconds: _fromSlider(v))),
            ),
            Row(
              children: [
                Text('courte', style: help),
                const Spacer(),
                Text('longue', style: help),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Combien de temps une note jouée continue de compter. Courte : '
              'seules les notes qu\'on vient de jouer comptent, celles qui '
              'résonnent encore s\'effacent. Longue : pour les arpèges, quand '
              'on égrène l\'accord note à note.',
              style: help,
            ),
          ],
        ),
      ),
    );
  }
}
