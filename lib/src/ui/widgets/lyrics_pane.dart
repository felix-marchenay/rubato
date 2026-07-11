import 'package:flutter/material.dart';

import '../../codec/chordpro_codec.dart';
import '../../data/catalog_repository.dart';
import '../../data/lrclib_service.dart';
import '../../data/lyrics_store.dart';
import '../../domain/lyric_sheet.dart';
import '../../domain/song.dart';
import '../theme.dart';
import 'lyric_sheet_view.dart';

/// Volet « Paroles » d'un morceau. Ordre de priorité des sources :
///  1. paroles conservées en local (récupérées puis enregistrées) ;
///  2. représentation `lyrics` embarquée (.pro fourni) ;
///  3. rien → état vide + bouton pour récupérer via LRCLIB.
///
/// À la récupération, les paroles sont écrites dans le stockage local
/// (fichier .pro sur Android) pour être conservées hors-ligne.
class LyricsPane extends StatefulWidget {
  final Song song;
  final CatalogRepository repository;
  final Representation? lyricsRep;

  const LyricsPane({
    super.key,
    required this.song,
    required this.repository,
    required this.lyricsRep,
  });

  @override
  State<LyricsPane> createState() => _LyricsPaneState();
}

class _LyricsPaneState extends State<LyricsPane> {
  static const _codec = ChordProCodec();
  final _lrclib = const LrclibService();
  final _store = const LyricsStore();

  bool _initializing = true;
  bool _fetching = false;
  bool _searched = false;
  bool _fromLrclib = false;
  String? _error;
  LyricSheet? _sheet;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 1. Paroles conservées localement (priorité : édition/récupération).
    final local = await _store.read(widget.song.id);
    if (!mounted) return;
    if (local != null && local.trim().isNotEmpty) {
      setState(() {
        _sheet = _codec.decode(local);
        _initializing = false;
      });
      return;
    }

    // 2. Paroles embarquées (.pro fourni avec l'app).
    if (widget.lyricsRep != null) {
      try {
        final sheet = await widget.repository.loadLyrics(widget.lyricsRep!);
        if (!mounted) return;
        setState(() {
          _sheet = sheet;
          _initializing = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = '$e';
          _initializing = false;
        });
      }
      return;
    }

    // 3. Rien : on proposera la récupération.
    setState(() => _initializing = false);
  }

  Future<void> _fetch() async {
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final raw = await _lrclib.fetchPlainLyrics(
        track: widget.song.title,
        artist: widget.song.artist,
      );
      if (!mounted) return;

      if (raw == null) {
        setState(() {
          _fetching = false;
          _searched = true;
        });
        return;
      }

      final pro = _toChordPro(raw);
      final saved = await _store.save(widget.song.id, pro);
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _searched = true;
        _fromLrclib = true;
        _sheet = _codec.decode(pro);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved
            ? 'Paroles enregistrées localement.'
            : 'Paroles affichées (conservation locale indisponible).'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = '$e';
      });
    }
  }

  /// Emballe les paroles brutes dans un .pro minimal (métadonnées + texte),
  /// prêt à être enrichi d'accords `[...]` plus tard.
  String _toChordPro(String rawLyrics) {
    final b = StringBuffer()..writeln('{title: ${widget.song.title}}');
    if (widget.song.artist != null) {
      b.writeln('{artist: ${widget.song.artist}}');
    }
    b
      ..writeln()
      ..write(rawLyrics);
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_fetching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Recherche sur LRCLIB…',
                style: TextStyle(color: context.palette.inkMuted)),
          ],
        ),
      );
    }

    if (_sheet != null) {
      final view = LyricSheetView(sheet: _sheet!);
      return _fromLrclib ? _Attributed(child: view) : view;
    }

    final String message;
    if (_error != null) {
      message = 'Impossible de récupérer les paroles.\n$_error';
    } else if (_searched) {
      message = 'Aucune parole trouvée sur LRCLIB pour ce morceau.';
    } else {
      message = 'Aucune parole pour ce morceau.';
    }
    return _Empty(
      message: message,
      actionLabel:
          (_searched || _error != null) ? 'Réessayer' : 'Récupérer les paroles',
      onAction: _fetch,
    );
  }
}

/// État vide / message centré, avec bouton d'action optionnel.
class _Empty extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Empty({required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, size: 40, color: p.line),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.inkMuted, height: 1.4),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.brass,
                  foregroundColor: p.onBrass,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Enveloppe une vue paroles récupérée en ligne d'une mention d'attribution.
class _Attributed extends StatelessWidget {
  final Widget child;
  const _Attributed({required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        Expanded(child: child),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: Text(
            'Paroles fournies par LRCLIB · conservées localement',
            textAlign: TextAlign.center,
            style: RubatoType.caption(p.inkMuted),
          ),
        ),
      ],
    );
  }
}
