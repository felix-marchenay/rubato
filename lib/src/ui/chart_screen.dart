import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../domain/chord_chart.dart';
import '../domain/song.dart';
import 'theme.dart';
import 'widgets/chord_grid_view.dart';
import 'widgets/lyrics_pane.dart';
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

  Representation? get _grid => widget.song.primaryChordGrid;
  Representation? get _score => widget.song.primaryScore;

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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ViewToggle(
                  mode: _mode,
                  onChanged: (m) => setState(() => _mode = m),
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
        final rep = _grid;
        if (rep == null) {
          return const _Message('Pas de grille d\'accords pour ce morceau.');
        }
        return FutureBuilder<ChordChart>(
          future: widget.repository.loadChart(rep),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Message('Erreur de chargement : ${snapshot.error}');
            }
            return ChordGridView(chart: snapshot.data!);
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

/// Sélecteur Grille · Paroles · Mélodie, façon pilule (DA « Encre & Papier »).
class _ViewToggle extends StatelessWidget {
  final _ViewMode mode;
  final ValueChanged<_ViewMode> onChanged;
  const _ViewToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(context, 'Grille', _ViewMode.grid),
          _seg(context, 'Paroles', _ViewMode.lyrics),
          _seg(context, 'Mélodie', _ViewMode.melody),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, _ViewMode value) {
    final p = context.palette;
    final active = mode == value;
    return GestureDetector(
      onTap: active ? null : () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? p.brass : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? p.onBrass : p.inkMuted,
          ),
        ),
      ),
    );
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
