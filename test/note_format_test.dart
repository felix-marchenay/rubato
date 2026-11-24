import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/ui/note_format.dart';

void main() {
  test('octaves à la française : Do3 = do central, La3 = 440 Hz', () {
    expect('${NoteName.ofMidi(60)}', 'Do3');
    expect('${NoteName.ofMidi(69)}', 'La3');
    expect('${NoteName.ofMidi(40)}', 'Mi1', reason: 'Mi grave de la guitare');
    expect('${NoteName.ofMidi(36)}', 'Do1');
    expect('${NoteName.ofMidi(21)}', 'La-1', reason: 'note la plus grave du piano');
    expect('${NoteName.ofMidi(59)}', 'Si2', reason: 'l\'octave change au do');
    expect('${NoteName.ofMidi(61)}', 'Ré♭3');
    expect('${NoteName.ofMidi(66)}', 'Fa♯3');
  });
}
