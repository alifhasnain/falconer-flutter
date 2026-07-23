// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:dio/dio.dart';
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

  testWidgets('capture persists a transaction and the live count increments', (
    WidgetTester tester,
  ) async {
    await Falconer.clear();
    await Falconer.configure(const FalconerConfig(enabled: true));

    // A request to a dead local port fails fast with no network — the error is
    // still captured (logError -> stored), so this exercises the native
    // capture -> SQLite -> count pipeline offline.
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)))
      ..interceptors.add(FalconerInterceptor());
    try {
      await dio.get<void>('http://127.0.0.1:9/falconer-offline-probe');
    } catch (_) {
      // Expected: connection refused / timeout. The transaction is captured.
    }

    final int count = await Falconer.transactionCount
        .firstWhere((c) => c >= 1)
        .timeout(const Duration(seconds: 8));
    expect(count, greaterThanOrEqualTo(1));

    // launchUi presents the inspector window; it must not throw. clear() wipes
    // storage and dismisses it.
    await Falconer.launchUi();
    await tester.pump(const Duration(milliseconds: 300));
    await Falconer.clear();
  });
}
