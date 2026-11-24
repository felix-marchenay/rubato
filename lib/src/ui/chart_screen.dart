import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../domain/chord_chart.dart';
import '../domain/song.dart';
import 'practice_view.dart';
import 'theme.dart';
import 'widgets/chord_grid_view.dart';
import 'widgets/lyrics_pane.dart';
import 'widgets/pill_toggle.dart';
import 'widgets/score_view.dart';

enum _ViewMode { grid, lyrics, melody }

/// Écran de lecture : bascule entre la grille d'accords, les paroles et la
/// mélodie (partition). Le sélecteur de vue est toujours affiché en haut.
class ChartScreen extends StatefulWidget {
  final Song song;
  final LibraryRepository repository;

  const ChartScreen({super.key, required this.song, required this.repository});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late _ViewMode _mode;

  /// Mode entraînement : le micro valide les accords de la grille un à un.
  bool _practicing = false;

  Representation? get _grid => widget.song.primaryChordGrid;
  Representation? get _score => widget.song.primaryScore;

  // Chargée une fois : l'écran se reconstruit souvent (changement de vue).
  late final Future<ChordChart>? _chart =
      _grid == null ? null : widget.repository.loadChart(_grid!);

  @override
  void initState() {
    super.initState();
    // Vue par défaut : grille si dispo, sinon paroles, sinon mélodie.
    _mode = _grid != null
        ? _ViewMode.grid
        : widget.song.primaryLyrics != null
            ? _ViewMode.lyrics
            : _score != null
                ? _ViewMode.melody
                : _ViewMode.lyrics;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final song = widget.song;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              song.title,
              style: RubatoType.serif(
                  size: 19, weight: FontWeight.w600, color: p.ink),
              overflow: TextOverflow.ellipsis,
            ),
            if (song.artist != null)
              Text(
                song.artist!,
                style: TextStyle(fontSize: 12, color: p.inkMuted),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if (_mode == _ViewMode.grid && _grid != null)
            IconButton(
              onPressed: () => setState(() => _practicing = !_practicing),
              icon: Icon(_practicing ? Icons.close : Icons.graphic_eq),
              color: p.brass,
              tooltip: _practicing
                  ? 'Arrêter l\'entraînement'
                  : 'S\'entraîner : jouer les accords un à un',
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PillToggle<_ViewMode>(
                  value: _mode,
                  options: const {
                    _ViewMode.grid: 'Grille',
                    _ViewMode.lyrics: 'Paroles',
                    _ViewMode.melody: 'Mélodie',
                  },
                  onChanged: (m) => setState(() {
                    _mode = m;
                    _practicing = false;
                  }),
                ),
              ),
              Container(height: 1, color: p.line),
            ],
          ),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    switch (_mode) {
      case _ViewMode.grid:
        if (_chart == null) {
          return const _Message('Pas de grille d\'accords pour ce morceau.');
        }
        return FutureBuilder<ChordChart>(
          future: _chart,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Message('Erreur de chargement : ${snapshot.error}');
            }
            final chart = snapshot.data!;
            return _practicing
                ? PracticeView(chart: chart)
                : ChordGridView(chart: chart);
          },
        );
      case _ViewMode.lyrics:
        return LyricsPane(
          song: widget.song,
          repository: widget.repository,
          lyricsRep: widget.song.primaryLyrics,
        );
      case _ViewMode.melody:
        final rep = _score;
        if (rep == null) {
          return const _Message(
            'Aucune partition mélodie pour ce morceau.\n'
            'On peut en ajouter une au format ABC (assets/scores/<id>.abc).',
          );
        }
        return ScoreView(
          song: widget.song,
          repository: widget.repository,
          scoreRep: rep,
        );
    }
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.palette.inkMuted, height: 1.4),
          ),
        ),
      );
}
