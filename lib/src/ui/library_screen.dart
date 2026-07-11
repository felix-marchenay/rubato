import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../domain/song.dart';
import 'chart_screen.dart';
import 'online_search_screen.dart';
import 'theme.dart';

/// Écran bibliothèque : table des matières du carnet + recherche.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _repository = const LibraryRepository();
  late Future<List<Song>> _songsFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _songsFuture = _repository.loadSongs();
  }

  void _reload() {
    setState(() => _songsFuture = _repository.loadSongs());
  }

  Future<void> _openOnlineSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnlineSearchScreen(repository: _repository),
      ),
    );
    // La bibliothèque perso a pu changer : on recharge la liste au retour.
    if (mounted) _reload();
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
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const _Wordmark(),
        actions: [
          IconButton(
            onPressed: _openOnlineSearch,
            icon: const Icon(Icons.travel_explore),
            color: p.brass,
            tooltip: 'Chercher un morceau en ligne',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
        ),
      ),
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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Rechercher un morceau, un artiste…',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Text(
                      songs.length.toString().padLeft(2, '0'),
                      style: RubatoType.caption(p.brass),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      songs.length > 1 ? 'MORCEAUX' : 'MORCEAU',
                      style: RubatoType.caption(p.inkMuted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: songs.isEmpty
                    ? Center(
                        child: Text('Aucun morceau.',
                            style: TextStyle(color: p.inkMuted)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: songs.length,
                        itemBuilder: (context, i) => _SongTile(
                          index: i + 1,
                          song: songs[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ChartScreen(
                                song: songs[i],
                                repository: _repository,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Logo texte « rubato » en serif, avec une baseline laiton discrète.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'rubato',
          style: RubatoType.serif(
            size: 26,
            weight: FontWeight.w600,
            color: p.ink,
            style: FontStyle.italic,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text('CARNET D’ACCORDS', style: RubatoType.caption(p.brass)),
        ),
      ],
    );
  }
}

/// Ligne de morceau, façon table des matières : numéro laiton, titre gravé,
/// artiste + tags atténués, filet de séparation.
class _SongTile extends StatelessWidget {
  final int index;
  final Song song;
  final VoidCallback onTap;

  const _SongTile({
    required this.index,
    required this.song,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tags = song.tags.join('  ·  ');
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.line)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 34,
              child: Text(
                index.toString().padLeft(2, '0'),
                style: RubatoType.serif(
                  size: 15,
                  weight: FontWeight.w500,
                  color: p.brass,
                  style: FontStyle.italic,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: RubatoType.serif(
                        size: 18, weight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (song.artist != null) song.artist!,
                      if (tags.isNotEmpty) tags,
                    ].join('   —   '),
                    style: TextStyle(fontSize: 12.5, color: p.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 20, color: p.line),
          ],
        ),
      ),
    );
  }
}
