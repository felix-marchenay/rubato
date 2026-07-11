import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/catalog_repository.dart';
import '../../domain/song.dart';
import '../theme.dart';

/// Vue « mélodie » : rend une partition en notation **ABC** via **abcjs**
/// (embarqué hors-ligne dans assets/abcjs) à l'intérieur d'une WebView. Rendu
/// façon real book : une portée en clef de sol, accords affichés au-dessus.
class ScoreView extends StatefulWidget {
  final Song song;
  final CatalogRepository repository;
  final Representation scoreRep;

  const ScoreView({
    super.key,
    required this.song,
    required this.repository,
    required this.scoreRep,
  });

  @override
  State<ScoreView> createState() => _ScoreViewState();
}

class _ScoreViewState extends State<ScoreView> {
  late final Future<_Sources> _future;
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Sources> _load() async {
    final abc = await widget.repository.loadScoreSource(widget.scoreRep);
    final abcjs = await rootBundle.loadString('assets/abcjs/abcjs-basic-min.js');
    return _Sources(abc: abc, abcjs: abcjs);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FutureBuilder<_Sources>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Erreur de chargement : ${snap.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.inkMuted)),
            ),
          );
        }
        // Contrôleur construit une seule fois, avec la palette courante.
        _controller ??= _makeController(snap.data!, p);
        return WebViewWidget(controller: _controller!);
      },
    );
  }

  WebViewController _makeController(_Sources s, RubatoPalette p) {
    final controller = WebViewController();
    try {
      controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    } catch (_) {}
    try {
      controller.setBackgroundColor(p.paper);
    } catch (_) {}
    controller.loadHtmlString(_html(s, p));
    return controller;
  }

  String _html(_Sources s, RubatoPalette p) {
    final bg = _hex(p.paper);
    final ink = _hex(p.ink);
    final brass = _hex(p.brass);
    final abcJson = jsonEncode(s.abc);
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  html, body { margin:0; padding:0; background:$bg; }
  #paper { padding:16px; }
  #paper svg { max-width:100%; }
  #paper svg path { fill:$ink; }
  #paper svg .abcjs-staff path, #paper svg .abcjs-bar path { stroke:$ink; }
  #paper svg text { fill:$ink; }
  #paper svg .abcjs-annotation, #paper svg .abcjs-chord { fill:$brass !important; }
  #err { font-family:sans-serif; color:$ink; padding:16px; }
</style>
</head>
<body>
<div id="paper"></div>
<script>${s.abcjs}</script>
<script>
  (function(){
    try {
      ABCJS.renderAbc("paper", $abcJson, {
        responsive: "resize",
        add_classes: true,
        foregroundColor: "$ink",
        paddingtop: 4, paddingbottom: 4, paddingleft: 0, paddingright: 0
      });
    } catch (e) {
      var el = document.getElementById("paper");
      el.textContent = "Partition illisible : " + e;
    }
  })();
</script>
</body>
</html>
''';
  }

  String _hex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

class _Sources {
  final String abc;
  final String abcjs;
  const _Sources({required this.abc, required this.abcjs});
}
