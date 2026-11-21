import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/chord_detector.dart';
import '../audio/listening_controller.dart';
import '../audio/practice.dart';
import '../domain/chord_chart.dart';
import 'chord_format.dart';
import 'theme.dart';
import 'widgets/chord_grid_view.dart';
import 'widgets/listening_widgets.dart';

/// Mode entraînement : la grille du morceau, et un panneau qui écoute ce
/// qu'on joue pour valider les accords un à un, dans l'ordre de la grille.
class PracticeView extends StatefulWidget {
  final ChordChart chart;
  const PracticeView({super.key, required this.chart});

  @override
  State<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends State<PracticeView> {
  late final _session = PracticeSession(practiceSteps(widget.chart));
  late final _listening = ListeningController(onFrame: _onFrame);

  /// Du premier accord validé au dernier.
  final _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listening.start());
  }

  @override
  void dispose() {
    _listening.dispose();
    super.dispose();
  }

  void _onFrame(ListeningFrame frame) {
    if (!_session.onFrame(frame)) return;
    HapticFeedback.selectionClick();
    if (!_stopwatch.isRunning && _session.index == 1) _stopwatch.start();
    if (_session.finished) _stopwatch.stop();
    setState(() {});
  }

  void _jumpTo(int i) {
    setState(() {
      _session.jumpTo(i);
      _stopwatch
        ..stop()
        ..reset();
    });
  }

  GridHighlight _highlight() {
    final current = _session.current;
    return GridHighlight(
      current: {...?current?.refs},
      done: {
        for (final step in _session.steps.take(_session.index)) ...step.refs,
      },
      reveal: current?.refs.first,
      onTap: (ref) {
        final i = _session.stepOf(ref);
        if (i != null) _jumpTo(i);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_session.steps.isEmpty) {
      return Center(
        child: Text(
          'Aucun accord à jouer dans cette grille.',
          style: TextStyle(color: context.palette.inkMuted),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ChordGridView(chart: widget.chart, highlight: _highlight()),
        ),
        ListenableBuilder(
          listenable: _listening,
          builder: (context, _) => ValueListenableBuilder<ListeningFrame?>(
            valueListenable: _listening.frame,
            builder: (context, frame, _) => PracticePanel(
              session: _session,
              status: _listening.status,
              frame: _listening.isListening ? frame : null,
              gateDb: _listening.detector.gateDb,
              elapsed: _stopwatch.elapsed,
              onToggleMic: _listening.toggle,
              onRetryMic: _listening.start,
              onRestart: () => _jumpTo(0),
              onPrevious: () => _jumpTo(_session.index - 1),
              onNext: () => _jumpTo(_session.index + 1),
            ),
          ),
        ),
      ],
    );
  }
}

/// Panneau du bas : accord à jouer, suivant, entendu, progression et
/// commandes. Pur affichage : l'état du micro lui est passé.
class PracticePanel extends StatelessWidget {
  final PracticeSession session;
  final MicStatus status;
  final ListeningFrame? frame;
  final double gateDb;
  final Duration elapsed;
  final VoidCallback onToggleMic;
  final VoidCallback onRetryMic;
  final VoidCallback onRestart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const PracticePanel({
    super.key,
    required this.session,
    required this.status,
    required this.frame,
    required this.gateDb,
    required this.elapsed,
    required this.onToggleMic,
    required this.onRetryMic,
    required this.onRestart,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(p),
              const SizedBox(height: 12),
              switch (status) {
                MicStatus.denied || MicStatus.failed => _micProblem(p),
                _ when session.finished => _finished(p),
                _ => _chords(p),
              },
              const SizedBox(height: 12),
              _controls(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(RubatoPalette p) {
    final f = frame;
    final listeningNow = status == MicStatus.listening;
    return Row(
      children: [
        Text(
          switch (status) {
            MicStatus.listening => 'À L\'ÉCOUTE',
            MicStatus.starting => 'OUVERTURE DU MICRO…',
            _ => 'EN PAUSE',
          },
          style: RubatoType.caption(listeningNow ? p.brass : p.inkMuted),
        ),
        const SizedBox(width: 12),
        if (f != null)
          SizedBox(
            width: 56,
            child: LevelMeter(levelDb: f.levelDb, gateDb: gateDb),
          ),
        const Spacer(),
        Text(
          '${session.index.clamp(0, session.steps.length)} / '
          '${session.steps.length}',
          style: RubatoType.caption(p.inkMuted),
        ),
      ],
    );
  }

  Widget _chords(RubatoPalette p) {
    final step = session.current!;
    final next = session.next;
    final heard = frame?.chord?.toChord();
    final hearing = session.hearing;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 5,
          child: _Labelled(
            label: 'JOUE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChordLabel(
                  chord: step.chord,
                  size: 40,
                  color: hearing ? p.brass : p.ink,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: session.confirmation,
                    minHeight: 3,
                    backgroundColor: p.line,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _Labelled(
            label: 'ENSUITE',
            child: next == null
                ? Text('fin', style: RubatoType.serif(size: 20, color: p.inkMuted))
                : _ChordLabel(chord: next.chord, size: 22, color: p.inkMuted),
          ),
        ),
        Expanded(
          flex: 3,
          child: _Labelled(
            label: 'ENTENDU',
            child: heard == null || !(frame?.hasSignal ?? false)
                ? Text('—', style: RubatoType.serif(size: 22, color: p.line))
                : _ChordLabel(
                    chord: heard,
                    size: 22,
                    color: hearing ? p.brass : p.ink,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _finished(RubatoPalette p) {
    final s = elapsed.inSeconds;
    final duration = s >= 60 ? '${s ~/ 60} min ${s % 60} s' : '$s s';
    return Row(
      children: [
        Icon(Icons.check_circle, color: p.brass, size: 32),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bravo, grille jouée en entier !',
                  style: RubatoType.serif(size: 18, color: p.ink)),
              const SizedBox(height: 2),
              Text(
                '${session.steps.length} accords'
                '${elapsed > Duration.zero ? ' en $duration' : ''}.',
                style: TextStyle(color: p.inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _micProblem(RubatoPalette p) => Row(
        children: [
          Icon(Icons.mic_off, color: p.inkMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status == MicStatus.denied
                  ? 'Le micro est refusé : autorise-le dans les réglages pour '
                      's\'entraîner.'
                  : 'Impossible d\'ouvrir le micro.',
              style: TextStyle(color: p.inkMuted, height: 1.3),
            ),
          ),
          TextButton(onPressed: onRetryMic, child: const Text('Réessayer')),
        ],
      );

  Widget _controls(RubatoPalette p) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: session.index > 0 ? onRestart : null,
            icon: const Icon(Icons.replay),
            tooltip: 'Recommencer',
          ),
          IconButton(
            onPressed: session.index > 0 ? onPrevious : null,
            icon: const Icon(Icons.skip_previous),
            tooltip: 'Accord précédent',
          ),
          MicButton(status: status, onPressed: onToggleMic, size: 56),
          IconButton(
            onPressed: session.finished ? null : onNext,
            icon: const Icon(Icons.skip_next),
            tooltip: 'Passer cet accord',
          ),
        ],
      );
}

class _Labelled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labelled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: RubatoType.caption(context.palette.inkMuted)),
          const SizedBox(height: 4),
          child,
        ],
      );
}

/// Accord gravé (racine + qualité en exposant + basse), réduit si besoin.
class _ChordLabel extends StatelessWidget {
  final Chord chord;
  final double size;
  final Color color;
  const _ChordLabel({required this.chord, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    final parts = ChordFormat.parts(chord);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: parts.root,
            style: RubatoType.serif(size: size, color: color, height: 1),
          ),
          if (parts.quality.isNotEmpty)
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  parts.quality,
                  style: RubatoType.serif(size: size * 0.55, color: color, height: 1),
                ),
              ),
            ),
          if (parts.bass != null)
            TextSpan(
              text: '/${parts.bass}',
              style: RubatoType.serif(
                  size: size * 0.6,
                  weight: FontWeight.w500,
                  color: context.palette.inkMuted,
                  height: 1),
            ),
        ]),
      ),
    );
  }
}
