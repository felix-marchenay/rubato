import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../audio/chord_detector.dart';
import '../audio/chord_matcher.dart';
import '../audio/chord_vocabulary.dart' show pitchClassNames;
import '../audio/listening_controller.dart';
import '../domain/chord_chart.dart';
import 'chord_format.dart';
import 'theme.dart';
import 'widgets/listening_settings_sheet.dart';
import 'widgets/listening_widgets.dart';
import 'widgets/note_label.dart';

/// Écran « Écouter » : le micro entend la musique jouée, l'écran affiche
/// l'accord reconnu, les notes perçues et les derniers accords.
class ListenScreen extends StatefulWidget {
  const ListenScreen({super.key});

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  late final _listening = ListeningController(onFrame: _onFrame);

  /// Derniers accords entendus, du plus ancien au plus récent.
  final _history = <Chord>[];
  static const _historyLength = 8;
  ChordCandidate? _lastShown;

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

  void _onFrame(ListeningFrame f) {
    final c = f.chord;
    if (c != null && (_lastShown == null || !c.sameChordAs(_lastShown!))) {
      _lastShown = c;
      _history.add(c.toChord());
      if (_history.length > _historyLength) _history.removeAt(0);
    }
  }

  Future<void> _openSettings() => showListeningSettings(context, _listening);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Text(
          'Écouter',
          style: RubatoType.serif(size: 19, color: p.ink),
        ),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.tune),
            tooltip: 'Réglages de l\'écoute',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _listening,
          builder: (context, _) => switch (_listening.status) {
            MicStatus.denied ||
            MicStatus.failed =>
              MicProblem(controller: _listening),
            _ => ValueListenableBuilder<ListeningFrame?>(
                valueListenable: _listening.frame,
                builder: (context, frame, _) => _content(frame),
              ),
          },
        ),
      ),
    );
  }

  Widget _content(ListeningFrame? frame) {
    final status = _listening.status;
    final listening = _listening.isListening;
    final chord = frame?.chord;
    final note = frame?.note;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: _StatusLine(
            status: status,
            frame: listening ? frame : null,
            gateDb: _listening.detector.gateDb,
          ),
        ),
        Expanded(
          child: Center(
            child: _BigChord(
              chord: chord?.toChord(),
              note: note,
              held: !listening || (frame != null && !frame.hasSignal),
              hint: listening
                  ? 'Joue un accord ou une note près du téléphone.'
                  : 'Touche le micro pour écouter.',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ChromaBars(
            chroma: listening ? frame?.chroma : null,
            chord: chord,
            notePc: note == null ? null : note % 12,
          ),
        ),
        const SizedBox(height: 20),
        _History(chords: _history),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
          child: MicButton(status: status, onPressed: _listening.toggle),
        ),
      ],
    );
  }
}

/// « À L'ÉCOUTE » + vumètre + accordage estimé.
class _StatusLine extends StatelessWidget {
  final MicStatus status;
  final ListeningFrame? frame;
  final double gateDb;

  const _StatusLine({
    required this.status,
    required this.frame,
    required this.gateDb,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = frame;
    final label = switch (status) {
      MicStatus.listening => 'À L\'ÉCOUTE',
      MicStatus.starting => 'OUVERTURE DU MICRO…',
      _ => 'EN PAUSE',
    };
    return Row(
      children: [
        Text(
          label,
          style: RubatoType.caption(
              status == MicStatus.listening ? p.brass : p.inkMuted),
        ),
        const SizedBox(width: 12),
        if (f != null)
          SizedBox(
            width: 64,
            child: LevelMeter(levelDb: f.levelDb, gateDb: gateDb),
          ),
        const Spacer(),
        if (f != null)
          Text(
            'LA ${(440 * math.pow(2, f.tuningCents / 1200)).round()} HZ',
            style: RubatoType.caption(p.inkMuted),
          ),
      ],
    );
  }
}

/// L'accord reconnu (ou la note jouée seule), gravé en grand. Atténué quand
/// le son s'est tu.
class _BigChord extends StatelessWidget {
  final Chord? chord;
  final int? note;
  final bool held;
  final String hint;

  const _BigChord({
    required this.chord,
    required this.note,
    required this.held,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = chord;
    final n = note;
    final Widget content;
    if (n != null) {
      content = Padding(
        key: ValueKey('note$n'),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: NoteLabel(
            midi: n,
            size: 140,
            color: p.ink,
            octaveColor: p.brass,
          ),
        ),
      );
    } else if (c == null) {
      content = Column(
        key: const ValueKey('none'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '—',
            style: RubatoType.serif(
                size: 96, weight: FontWeight.w300, color: p.line, height: 1),
          ),
          const SizedBox(height: 12),
          Text(hint, style: TextStyle(color: p.inkMuted)),
        ],
      );
    } else {
      final parts = ChordFormat.parts(c);
      content = Padding(
        key: ValueKey(c.raw),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: parts.root,
                style: RubatoType.serif(
                    size: 140, weight: FontWeight.w600, color: p.ink, height: 1),
              ),
              if (parts.quality.isNotEmpty)
                WidgetSpan(
                  alignment: PlaceholderAlignment.top,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      parts.quality,
                      style: RubatoType.serif(
                          size: 64,
                          weight: FontWeight.w600,
                          color: p.brass,
                          height: 1),
                    ),
                  ),
                ),
              if (parts.bass != null)
                TextSpan(
                  text: '/${parts.bass}',
                  style: RubatoType.serif(
                      size: 72,
                      weight: FontWeight.w500,
                      color: p.inkMuted,
                      height: 1),
                ),
            ]),
          ),
        ),
      );
    }
    return AnimatedOpacity(
      opacity: held ? 0.4 : 1,
      duration: const Duration(milliseconds: 400),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: content,
      ),
    );
  }
}

/// Les 12 classes de hauteur perçues ; celles de l'accord reconnu en laiton.
class _ChromaBars extends StatelessWidget {
  final Float64List? chroma;
  final ChordCandidate? chord;

  /// Classe de hauteur de la note jouée seule, mise en laiton.
  final int? notePc;

  const _ChromaBars({
    required this.chroma,
    required this.chord,
    this.notePc,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var pc = 0; pc < 12; pc++)
            Expanded(child: _bar(context, pc, p)),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, int pc, RubatoPalette p) {
    final c = chord;
    final inChord = (c != null && c.template.contains(pc)) || notePc == pc;
    final isRoot = (c != null && c.root == pc) || notePc == pc;
    final value = chroma?[pc] ?? 0;
    final color = isRoot
        ? p.brass
        : inChord
            ? p.brass.withValues(alpha: 0.55)
            : p.inkMuted.withValues(alpha: 0.3);
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: math.max(0.02, value),
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(2)),
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(height: 1, color: p.line),
        const SizedBox(height: 6),
        Text(
          pitchClassNames[pc],
          style: TextStyle(
            fontSize: 11,
            fontWeight: inChord ? FontWeight.w800 : FontWeight.w600,
            color: inChord ? p.brass : p.inkMuted,
          ),
        ),
      ],
    );
  }
}

/// Bandeau des derniers accords, le plus récent à droite.
class _History extends StatelessWidget {
  final List<Chord> chords;

  const _History({required this.chords});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (chords.isEmpty) return const SizedBox(height: 32);
    return SizedBox(
      height: 32,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            for (var i = 0; i < chords.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Opacity(
                  opacity: 0.35 + 0.65 * (i + 1) / chords.length,
                  child: Text(
                    ChordFormat.display(chords[i]),
                    style: RubatoType.serif(
                      size: i == chords.length - 1 ? 22 : 18,
                      weight: FontWeight.w600,
                      color: i == chords.length - 1 ? p.ink : p.inkMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
