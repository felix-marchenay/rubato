import 'package:flutter_test/flutter_test.dart';
import 'package:mscore/src/ui/app.dart';

void main() {
  testWidgets('L\'appli démarre sur la bibliothèque', (tester) async {
    await tester.pumpWidget(const RubatoApp());
    // Le logo « rubato » est présent dès le premier rendu.
    expect(find.text('rubato'), findsOneWidget);
  });
}
