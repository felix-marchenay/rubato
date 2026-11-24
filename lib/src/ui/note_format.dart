/// Nom d'une note avec son octave, selon l'usage français : Do3 est le do
/// central du piano et La3 vaut 440 Hz (C4 et A4 en notation anglo-saxonne),
/// le Mi grave de la guitare est un Mi1.
class NoteName {
  static const _names = [
    'Do', 'Ré♭', 'Ré', 'Mi♭', 'Mi', 'Fa', 'Fa♯', 'Sol', 'La♭', 'La', 'Si♭', 'Si', //
  ];

  /// Nom sans octave (« Sol », « Si♭ »).
  final String name;
  final int octave;

  NoteName.ofMidi(int midi)
      : name = _names[midi % 12],
        octave = (midi ~/ 12) - 2;

  @override
  String toString() => '$name$octave';
}
