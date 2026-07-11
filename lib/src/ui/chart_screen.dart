import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../domain/chord_chart.dart';
import '../domain/song.dart';
import 'widgets/chord_grid_view.dart';

/// Écran de lecture : affiche la grille d'accords d'un morceau.
class ChartScreen extends StatelessWidget {
  final Song song;
  final CatalogRepository repository;

  const ChartScreen({super.key, required this.song, required this.repository});

  @override
  Widget build(BuildContext context) {
    final rep = song.primaryChordGrid;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(song.title, style: const TextStyle(fontSize: 18)),
            if (song.artist != null)
              Text(
                song.artist!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
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
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
