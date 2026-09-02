import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_fortune/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const LuminaFortuneApp());
    expect(find.byType(LuminaFortuneApp), findsOneWidget);
  });
}
