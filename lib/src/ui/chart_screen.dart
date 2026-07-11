import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../domain/chord_chart.dart';
import '../domain/lyric_sheet.dart';
import '../domain/song.dart';
import 'theme.dart';
import 'widgets/chord_grid_view.dart';
import 'widgets/lyric_sheet_view.dart';

enum _ViewMode { grid, lyrics }

/// Écran de lecture : bascule entre la grille d'accords et la feuille
/// paroles + accords (ChordPro) selon les représentations disponibles.
class ChartScreen extends StatefulWidget {
  final Song song;
  final CatalogRepository repository;

  const ChartScreen({super.key, required this.song, required this.repository});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late _ViewMode _mode;

  Representation? get _grid => widget.song.primaryChordGrid;
  Representation? get _lyrics => widget.song.primaryLyrics;
  bool get _canToggle => _grid != null && _lyrics != null;

  @override
  void initState() {
    super.initState();
    _mode = _grid != null ? _ViewMode.grid : _ViewMode.lyrics;
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
          if (_canToggle)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _ViewToggle(
                mode: _mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
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
        final rep = _lyrics;
        if (rep == null) {
          return const _Message('Pas de paroles pour ce morceau.');
        }
        return FutureBuilder<LyricSheet>(
          future: widget.repository.loadLyrics(rep),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Message('Erreur de chargement : ${snapshot.error}');
            }
            return LyricSheetView(sheet: snapshot.data!);
          },
        );
    }
  }
}

/// Bascule compacte Grille ⇄ Paroles, façon pilule (direction « Encre & Papier »).
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
            style: TextStyle(color: context.palette.inkMuted),
          ),
        ),
      );
}
