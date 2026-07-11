import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/ui/app.dart';

void main() {
  testWidgets('L\'appli démarre sur la bibliothèque', (tester) async {
    await tester.pumpWidget(const MscoreApp());
    // La barre de titre "mscore" est présente dès le premier rendu.
    expect(find.text('mscore'), findsOneWidget);
  });
}
