import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../domain/song.dart';
import 'chart_screen.dart';

/// Écran bibliothèque : liste des morceaux du catalogue + recherche simple.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _repository = const CatalogRepository();
  late Future<List<Song>> _songsFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _songsFuture = _repository.loadSongs();
  }

  List<Song> _filter(List<Song> songs) {
    if (_query.trim().isEmpty) return songs;
    final q = _query.toLowerCase();
    return songs
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            (s.artist?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('mscore')),
      body: FutureBuilder<List<Song>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          final songs = _filter(snapshot.data!);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher un morceau ou un artiste',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: songs.isEmpty
                    ? const Center(child: Text('Aucun morceau.'))
                    : ListView.separated(
                        itemCount: songs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final song = songs[i];
                          return ListTile(
                            leading: const Icon(Icons.music_note),
                            title: Text(song.title),
                            subtitle: song.artist == null ? null : Text(song.artist!),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChartScreen(
                                  song: song,
                                  repository: _repository,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
