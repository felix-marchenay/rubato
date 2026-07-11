import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../domain/chord_chart.dart';
import '../domain/song.dart';
import 'theme.dart';
import 'widgets/chord_grid_view.dart';

/// Écran de lecture : affiche la grille d'accords d'un morceau.
class ChartScreen extends StatelessWidget {
  final Song song;
  final CatalogRepository repository;

  const ChartScreen({super.key, required this.song, required this.repository});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rep = song.primaryChordGrid;
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
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
        ),
      ),
      body: rep == null
          ? const _Message('Pas de grille d\'accords pour ce morceau.')
          : FutureBuilder<ChordChart>(
              future: repository.loadChart(rep),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _Message('Erreur de chargement : ${snapshot.error}');
                }
                return ChordGridView(chart: snapshot.data!);
              },
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
