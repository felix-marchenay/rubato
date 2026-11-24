import 'package:flutter/material.dart';

import '../note_format.dart';
import '../theme.dart';

/// Note gravée : son nom en serif, l'octave en petit chiffre en indice.
class NoteLabel extends StatelessWidget {
  final int midi;
  final double size;
  final Color color;
  final Color? octaveColor;

  const NoteLabel({
    super.key,
    required this.midi,
    required this.size,
    required this.color,
    this.octaveColor,
  });

  @override
  Widget build(BuildContext context) {
    final note = NoteName.ofMidi(midi);
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: note.name,
          style: RubatoType.serif(size: size, color: color, height: 1),
        ),
        WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: Padding(
            padding: EdgeInsets.only(left: size * 0.04),
            child: Text(
              '${note.octave}',
              style: RubatoType.serif(
                size: size * 0.45,
                color: octaveColor ?? color,
                height: 1,
              ),
            ),
          ),
        ),
      ]),
      semanticsLabel: note.toString(),
    );
  }
}
