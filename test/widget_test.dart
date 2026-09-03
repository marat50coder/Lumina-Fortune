import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_fortune/prism/cloak.dart';

void main() {
  test('cloak round-trips a small string', () {
    const String plain = 'lumina fortune';
    final String back = unseal(seal(plain));
    expect(back, plain);
  });

  test('cloak returns empty on empty input', () {
    expect(unseal(const <int>[]), '');
  });

  testWidgets('empty widget mounts', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
