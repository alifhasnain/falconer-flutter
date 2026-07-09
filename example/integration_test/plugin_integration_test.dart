// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:falconer/falconer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ping reaches the native channel', (WidgetTester tester) async {
    final String? reply = await Falconer.ping();
    expect(reply, 'pong');
  });

  testWidgets('requestNotificationPermission returns a bool', (
    WidgetTester tester,
  ) async {
    final bool granted = await Falconer.requestNotificationPermission();
    expect(granted, isTrue);
  });
}
