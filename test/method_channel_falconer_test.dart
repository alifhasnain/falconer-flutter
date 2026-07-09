import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:falconer/src/platform/method_channel_falconer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelFalconer platform = MethodChannelFalconer();
  const MethodChannel channel = MethodChannel('falconer');
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Records every method call routed to the native channel.
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    log.clear();
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      log.add(call);
      switch (call.method) {
        case 'ping':
          return 'pong';
        case 'requestNotificationPermission':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('ping sends "ping" and returns the reply', () async {
    expect(await platform.ping(), 'pong');
    expect(log.single.method, 'ping');
  });

  test('configure sends the config map', () async {
    await platform.configure(const {'enabled': true, 'maxContentLength': 10});
    expect(log.single.method, 'configure');
    expect(log.single.arguments, const {
      'enabled': true,
      'maxContentLength': 10,
    });
  });

  test('logRequest / logResponse / logError forward their payloads', () async {
    await platform.logRequest(const {'id': 'a'});
    await platform.logResponse(const {'id': 'a', 'statusCode': 200});
    await platform.logError(const {'id': 'a', 'error': 'boom'});

    expect(log.map((c) => c.method).toList(), [
      'logRequest',
      'logResponse',
      'logError',
    ]);
    expect(log[2].arguments, const {'id': 'a', 'error': 'boom'});
  });

  test('clearTransactions and launchUi send no arguments', () async {
    await platform.clearTransactions();
    await platform.launchUi();
    expect(log.map((c) => c.method).toList(), [
      'clearTransactions',
      'launchUi',
    ]);
    expect(log.every((c) => c.arguments == null), isTrue);
  });

  test('requestNotificationPermission returns the native bool', () async {
    expect(await platform.requestNotificationPermission(), isTrue);
    expect(log.single.method, 'requestNotificationPermission');
  });

  test(
    'requestNotificationPermission defaults to false on a null reply',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async => null,
      );
      expect(await platform.requestNotificationPermission(), isFalse);
    },
  );

  test('transactionCount decodes ints from the event channel', () async {
    const String name = 'falconer/transactionCount';
    const StandardMethodCodec codec = StandardMethodCodec();

    // Ack the EventChannel's outgoing listen/cancel control calls.
    messenger.setMockMethodCallHandler(
      const MethodChannel(name),
      (_) async => null,
    );

    final List<int> received = <int>[];
    final sub = platform.transactionCount.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    Future<void> emit(int value) => messenger.handlePlatformMessage(
      name,
      codec.encodeSuccessEnvelope(value),
      (_) {},
    );

    await emit(1);
    await emit(3);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(received, const [1, 3]);
  });
}
