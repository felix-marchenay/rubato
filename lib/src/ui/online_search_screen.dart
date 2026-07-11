import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../data/remote_catalog_service.dart';
import '../domain/song.dart';
import 'chart_screen.dart';
import 'theme.dart';

/// Recherche de morceaux en ligne via le proxy d'agrégation. Les résultats
/// affichent les représentations disponibles (Grille · Paroles · Mélodie) ;
/// « Ajouter » récupère les contenus et les conserve dans la bibliothèque perso.
class OnlineSearchScreen extends StatefulWidget {
  final LibraryRepository repository;

  const OnlineSearchScreen({super.key, required this.repository});

  @override
  State<OnlineSearchScreen> createState() => _OnlineSearchScreenState();
}

class _OnlineSearchScreenState extends State<OnlineSearchScreen> {
  static const _remote = RemoteCatalogService();
  final _controller = TextEditingController();

  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<RemoteSong> _results = const [];
  final Set<String> _adding = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final results = await _remote.search(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _add(RemoteSong song) async {
    setState(() => _adding.add(song.id));
    final added = <RepresentationType>[];
    String? failure;

    for (final type in song.available) {
      final ref = song.refs[type];
      if (ref == null) continue;
      try {
        final content = await _remote.fetchRepresentation(ref, type);
        final ok = await widget.repository.addRepresentation(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          type: type,
          content: content,
        );
        if (ok) {
          added.add(type);
        } else {
          failure = 'stockage local indisponible';
        }
      } catch (e) {
        failure = '$e';
      }
    }

    if (!mounted) return;
    setState(() => _adding.remove(song.id));

    if (added.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Échec de l\'ajout${failure != null ? ' : $failure' : ''}.'),
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ajouté à ta bibliothèque.')),
    );

    final newSong = Song(
      id: song.id,
      title: song.title,
      artist: song.artist,
      representations: [
        for (final t in added)
          LibraryRepository.storeRepresentation(song.id, t),
      ],
    );
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChartScreen(song: newSong, repository: widget.repository),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Text(
          'Recherche en ligne',
          style: RubatoType.serif(size: 19, weight: FontWeight.w600, color: p.ink),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Titre ou artiste…',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  onPressed: _search,
                ),
              ),
            ),
          ),
          Expanded(child: _body(p)),
        ],
      ),
    );
  }

  Widget _body(RubatoPalette p) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        text: 'Recherche indisponible.\n$_error',
      );
    }
    if (!_searched) {
      return const _Message(
        icon: Icons.travel_explore,
        text: 'Cherche un morceau : grilles d\'accords, paroles (LRCLIB) et '
            'mélodies du domaine public (The Session).',
      );
    }
    if (_results.isEmpty) {
      return const _Message(
        icon: Icons.search_off,
        text: 'Aucun résultat.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _results.length,
      itemBuilder: (context, i) => _ResultTile(
        song: _results[i],
        adding: _adding.contains(_results[i].id),
        onAdd: () => _add(_results[i]),
      ),
    );
  }
}

/// Une ligne de résultat : titre, artiste, pastilles de disponibilité, bouton.
class _ResultTile extends StatelessWidget {
  final RemoteSong song;
  final bool adding;
  final VoidCallback onAdd;

  const _ResultTile({
    required this.song,
    required this.adding,
    required this.onAdd,
  });

  static const _labels = {
    RepresentationType.chordGrid: 'Grille',
    RepresentationType.lyrics: 'Paroles',
    RepresentationType.score: 'Mélodie',
  };
  static const _order = [
    RepresentationType.chordGrid,
    RepresentationType.lyrics,
    RepresentationType.score,
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  style: RubatoType.serif(
                      size: 17, weight: FontWeight.w600, color: p.ink),
                ),
                if (song.artist != null) ...[
                  const SizedBox(height: 2),
                  Text(song.artist!,
                      style: TextStyle(fontSize: 12.5, color: p.inkMuted)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in _order)
                      if (song.has(t)) _Pill(label: _labels[t]!),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          adding
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline),
                  color: p.brass,
                  tooltip: 'Ajouter à ma bibliothèque',
                ),
        ],
      ),
    );
  }
}

/// Pastille de disponibilité (fond teinté laiton).
class _Pill extends StatelessWidget {
  final String label;
  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: p.brassTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: p.onBrassTint,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: p.line),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.inkMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
