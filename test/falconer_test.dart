import 'package:flutter_test/flutter_test.dart';
import 'package:falconer/falconer.dart';
import 'package:falconer/src/platform/falconer_platform.dart';
import 'package:falconer/src/platform/method_channel_falconer.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Records every call so the facade-forwarding can be asserted.
class MockFalconerPlatform
    with MockPlatformInterfaceMixin
    implements FalconerPlatform {
  final List<String> calls = <String>[];
  Map<String, dynamic>? lastConfig;

  @override
  Future<String?> ping() async {
    calls.add('ping');
    return 'pong';
  }

  @override
  Future<void> configure(Map<String, dynamic> config) async {
    calls.add('configure');
    lastConfig = config;
  }

  @override
  Future<void> logRequest(Map<String, dynamic> data) async =>
      calls.add('logRequest');

  @override
  Future<void> logResponse(Map<String, dynamic> data) async =>
      calls.add('logResponse');

  @override
  Future<void> logError(Map<String, dynamic> data) async =>
      calls.add('logError');

  @override
  Future<void> clearTransactions() async => calls.add('clearTransactions');

  @override
  Future<void> launchUi() async => calls.add('launchUi');

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('requestNotificationPermission');
    return true;
  }

  @override
  Stream<int> get transactionCount => Stream<int>.fromIterable(const [0, 1, 2]);
}

void main() {
  test('$MethodChannelFalconer is the default instance', () {
    expect(FalconerPlatform.instance, isInstanceOf<MethodChannelFalconer>());
  });

  group('Falconer facade forwards to the platform', () {
    late MockFalconerPlatform fake;

    setUp(() {
      fake = MockFalconerPlatform();
      FalconerPlatform.instance = fake;
    });

    test('ping', () async {
      expect(await Falconer.ping(), 'pong');
      expect(fake.calls, contains('ping'));
    });

    test('configure forwards the resolved config map', () async {
      await Falconer.configure(
        const FalconerConfig(
          maxContentLength: 50,
          retention: RetentionPeriod.oneWeek,
        ),
      );
      expect(fake.calls, contains('configure'));
      expect(fake.lastConfig?['maxContentLength'], 50);
      expect(fake.lastConfig?['retention'], 'oneWeek');
      expect(fake.lastConfig?['enabled'], isA<bool>());
    });

    test('configure defaults to the default config', () async {
      await Falconer.configure();
      expect(fake.lastConfig?['maxContentLength'], 250000);
    });

    test('launchUi', () async {
      await Falconer.launchUi();
      expect(fake.calls, contains('launchUi'));
    });

    test('clear maps to clearTransactions', () async {
      await Falconer.clear();
      expect(fake.calls, contains('clearTransactions'));
    });

    test('requestNotificationPermission returns the bool', () async {
      expect(await Falconer.requestNotificationPermission(), isTrue);
      expect(fake.calls, contains('requestNotificationPermission'));
    });

    test('transactionCount exposes the stream', () async {
      expect(await Falconer.transactionCount.toList(), const [0, 1, 2]);
    });
  });
}
