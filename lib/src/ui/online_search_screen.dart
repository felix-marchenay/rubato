import 'dart:async';

import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../data/remote_catalog_service.dart';
import '../data/search_cache.dart';
import '../domain/song.dart';
import 'chart_screen.dart';
import 'theme.dart';

/// Recherche de morceaux en ligne via le backend Go.
///
/// Deux principes :
///  - **au compte-gouttes** : le backend diffuse ses résultats en flux (SSE), on
///    affiche chaque morceau dès qu'il arrive plutôt que d'attendre la source la
///    plus lente ;
///  - **une seule fois** : une requête déjà faite est relue dans le cache local
///    ([SearchCache]) — instantané, hors-ligne, et sans re-solliciter les sites.
///    Le bouton « actualiser » force un nouvel appel.
class OnlineSearchScreen extends StatefulWidget {
  final LibraryRepository repository;

  const OnlineSearchScreen({super.key, required this.repository});

  @override
  State<OnlineSearchScreen> createState() => _OnlineSearchScreenState();
}

class _OnlineSearchScreenState extends State<OnlineSearchScreen> {
  static const _remote = RemoteCatalogService();
  static const _cache = SearchCache();

  final _controller = TextEditingController();
  StreamSubscription<SearchEvent>? _subscription;

  /// Requête affichée (celle des résultats à l'écran, pas celle du champ).
  String _query = '';
  bool _streaming = false;
  bool _searched = false;
  bool _fromCache = false;
  String? _error;
  List<RemoteSong> _results = const [];
  final List<SourceProgress> _progress = [];
  List<String> _recent = const [];
  final Set<String> _adding = {};

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _subscription?.cancel(); // coupe le flux SSE si on quitte l'écran
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final recent = await _cache.recentQueries();
    if (!mounted) return;
    setState(() => _recent = recent.take(8).toList());
  }

  /// Lance une recherche. Par défaut on sert le cache s'il a la réponse ;
  /// `refresh: true` l'oublie et repart du backend.
  Future<void> _search({bool refresh = false, String? query}) async {
    final q = (query ?? _controller.text).trim();
    if (q.length < 2) return;
    if (query != null) _controller.text = q;
    FocusScope.of(context).unfocus();

    await _subscription?.cancel();
    _subscription = null;

    if (refresh) {
      await _cache.forget(q);
    } else {
      final cached = await _cache.read(q);
      if (cached != null) {
        if (!mounted) return;
        setState(() {
          _query = q;
          _results = cached;
          _progress.clear();
          _fromCache = true;
          _streaming = false;
          _searched = true;
          _error = null;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _query = q;
      _results = const [];
      _progress.clear();
      _fromCache = false;
      _streaming = true;
      _searched = true;
      _error = null;
    });

    _subscription = _remote.searchStream(q).listen(
      (event) {
        if (!mounted) return;
        switch (event) {
          case SearchSongs(:final songs):
            setState(() => _results = songs);
          case SearchSourceDone(:final progress):
            setState(() => _progress.add(progress));
          case SearchDone():
            setState(() => _streaming = false);
            // Le flux est complet : c'est maintenant qu'on peut le mettre en
            // cache (une recherche partielle n'aurait aucun intérêt).
            _cache.write(q, _results).then((_) => _loadRecent());
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _error = '$e';
          _streaming = false;
        });
      },
      onDone: () {
        if (mounted && _streaming) setState(() => _streaming = false);
      },
    );
  }

  Future<void> _add(RemoteSong song) async {
    setState(() => _adding.add(song.id));
    final added = <RepresentationType>[];
    String? failure;

    for (final type in song.available) {
      final remote = song.contents[type];
      if (remote == null) continue;
      try {
        // Le contenu est déjà là (flux ou cache) : l'ajout est purement local.
        final ok = await widget.repository.addRepresentation(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          type: type,
          content: remote.content,
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
        actions: [
          if (_searched && !_streaming)
            IconButton(
              onPressed: () => _search(refresh: true, query: _query),
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Relancer la recherche (ignorer le cache)',
            ),
        ],
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
          if (_streaming || _fromCache) _StatusBar(
            streaming: _streaming,
            fromCache: _fromCache,
            progress: _progress,
            onRefresh: () => _search(refresh: true, query: _query),
          ),
          Expanded(child: _body(p)),
        ],
      ),
    );
  }

  Widget _body(RubatoPalette p) {
    // Pendant le flux, on affiche déjà ce qui est arrivé : le vide n'apparaît
    // qu'au tout début.
    if (_error != null && _results.isEmpty) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        text: 'Recherche indisponible.\n$_error',
      );
    }
    if (!_searched) {
      return _Welcome(recent: _recent, onPick: (q) => _search(query: q));
    }
    if (_results.isEmpty) {
      return _streaming
          ? const Center(child: CircularProgressIndicator())
          : const _Message(icon: Icons.search_off, text: 'Aucun résultat.');
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

/// Bandeau d'état sous la barre de recherche : avancement des sources pendant le
/// flux, ou rappel que les résultats viennent du cache.
class _StatusBar extends StatelessWidget {
  final bool streaming;
  final bool fromCache;
  final List<SourceProgress> progress;
  final VoidCallback onRefresh;

  const _StatusBar({
    required this.streaming,
    required this.fromCache,
    required this.progress,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(fontSize: 11.5, color: p.inkMuted);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (streaming) ...[
            SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                backgroundColor: p.line,
                color: p.brass,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text('Sources…', style: style),
                for (final s in progress)
                  Text(
                    s.failed
                        ? '${s.source} ✕'
                        : '${s.source} ${s.count > 0 ? '· ${s.count}' : '· —'} (${s.ms} ms)',
                    style: style.copyWith(
                      color: s.failed ? p.inkMuted : p.onBrassTint,
                    ),
                  ),
              ],
            ),
          ] else if (fromCache) ...[
            Row(
              children: [
                Icon(Icons.offline_bolt_outlined, size: 14, color: p.inkMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Résultats déjà connus (cache local).', style: style),
                ),
                TextButton(
                  onPressed: onRefresh,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Actualiser', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Écran d'accueil de la recherche : ce qu'on peut trouver, et les recherches
/// déjà en cache (un clic = résultat instantané, sans réseau).
class _Welcome extends StatelessWidget {
  final List<String> recent;
  final ValueChanged<String> onPick;

  const _Welcome({required this.recent, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.travel_explore, size: 40, color: p.line),
          const SizedBox(height: 16),
          Text(
            'Cherche un morceau : grilles d\'accords (corpus iReal, e-chords, '
            'Cifra Club, Ultimate Guitar) et paroles (LRCLIB).',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.inkMuted, height: 1.4),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'Déjà cherché',
              style: RubatoType.serif(
                  size: 13, weight: FontWeight.w600, color: p.inkMuted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final q in recent)
                  ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 12)),
                    onPressed: () => onPick(q),
                  ),
              ],
            ),
          ],
        ],
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
                    // La source est affichée avec la pastille : deux grilles du
                    // même morceau viennent parfois de sites différents.
                    for (final t in _order)
                      if (song.has(t))
                        _Pill(label: '${_labels[t]!} · ${song.sourceOf(t)}'),
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
