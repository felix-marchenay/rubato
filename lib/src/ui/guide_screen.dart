import 'package:flutter/material.dart';

import '../data/style_guides.dart';
import '../domain/style_guide.dart';
import 'style_guide_screen.dart';
import 'theme.dart';

/// Guide des styles : sommaire des fiches, regroupées par famille.
class GuideScreen extends StatefulWidget {
  final List<StyleGuide> guides;
  const GuideScreen({super.key, this.guides = styleGuides});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  String _query = '';

  bool _matches(StyleGuide g) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [g.name, g.tagline, g.family.label, ...g.artists]
        .any((s) => s.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final visible = widget.guides.where(_matches).toList();
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 20),
            hintText: 'Un style, un artiste…',
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      if (visible.isEmpty)
        Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Text('Aucun style.', style: TextStyle(color: p.inkMuted)),
          ),
        ),
      for (final family in StyleFamily.values)
        if (visible.any((g) => g.family == family)) ...[
          _FamilyHeader(family: family),
          for (final g in visible.where((g) => g.family == family))
            _StyleTile(
              guide: g,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StyleGuideScreen(guide: g)),
              ),
            ),
        ],
      const SizedBox(height: 24),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Text(
          'Guide des styles',
          style: RubatoType.serif(size: 20, weight: FontWeight.w600, color: p.ink),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.line),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(children: children),
        ),
      ),
    );
  }
}

class _FamilyHeader extends StatelessWidget {
  final StyleFamily family;
  const _FamilyHeader({required this.family});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Row(
        children: [
          Text(family.label.toUpperCase(), style: RubatoType.caption(p.brass)),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: p.line)),
        ],
      ),
    );
  }
}

class _StyleTile extends StatelessWidget {
  final StyleGuide guide;
  final VoidCallback onTap;
  const _StyleTile({required this.guide, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guide.name,
                    style: RubatoType.serif(size: 18, weight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    guide.tagline,
                    style: TextStyle(fontSize: 12.5, color: p.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${guide.tempo}',
                  style: RubatoType.serif(
                    size: 15,
                    weight: FontWeight.w500,
                    color: p.brass,
                    style: FontStyle.italic,
                  ),
                ),
                Text('BPM', style: RubatoType.caption(p.inkMuted).copyWith(fontSize: 9)),
              ],
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 20, color: p.line),
          ],
        ),
      ),
    );
  }
}
