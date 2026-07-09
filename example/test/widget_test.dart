// Basic smoke test for the demo app.

import 'package:flutter_test/flutter_test.dart';

import 'package:falconer_example/main.dart';

void main() {
  testWidgets('demo app renders its actions', (WidgetTester tester) async {
    await tester.pumpWidget(const DemoApp());

    expect(find.text('Falconer demo'), findsOneWidget);
    expect(find.text('JSON GET'), findsOneWidget);
    expect(find.text('Open inspector'), findsOneWidget);
  });
}
