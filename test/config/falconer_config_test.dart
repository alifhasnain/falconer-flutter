import 'package:falconer/falconer.dart';
import 'package:falconer/src/falconer_runtime.dart' as runtime;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FalconerConfig', () {
    test('defaults', () {
      const c = FalconerConfig();
      expect(c.maxContentLength, 250000);
      expect(c.retention, RetentionPeriod.oneWeek);
      expect(c.showNotification, true);
      expect(c.redactHeaders, contains('Authorization'));
    });

    test('resolveEnabled honours enabled in debug', () {
      expect(const FalconerConfig(enabled: true).resolveEnabled(false), isTrue);
      expect(
        const FalconerConfig(enabled: false).resolveEnabled(false),
        isFalse,
      );
    });

    test('resolveEnabled is always false in release', () {
      // No configuration can enable capture in a release build — `enabled: true`
      // included.
      expect(const FalconerConfig(enabled: true).resolveEnabled(true), isFalse);
      expect(
        const FalconerConfig(enabled: false).resolveEnabled(true),
        isFalse,
      );
      expect(
        const FalconerConfig().copyWith(enabled: true).resolveEnabled(true),
        isFalse,
      );
    });

    test('copyWith overrides only the given fields', () {
      const c = FalconerConfig();
      final c2 = c.copyWith(
        maxContentLength: 10,
        retention: RetentionPeriod.oneMonth,
      );
      expect(c2.maxContentLength, 10);
      expect(c2.retention, RetentionPeriod.oneMonth);
      expect(c2.enabled, c.enabled);
      expect(c2.redactHeaders, c.redactHeaders);
    });

    test('toMap carries the resolved state and wire keys', () {
      const c = FalconerConfig(
        enabled: true,
        maxContentLength: 99,
        retention: RetentionPeriod.oneWeek,
        showNotification: false,
      );
      final m = c.toMap();
      expect(m['enabled'], isA<bool>());
      expect(m['maxContentLength'], 99);
      expect(m['retention'], 'oneWeek');
      expect(m['showNotification'], false);
      expect(m['redactHeaders'], containsAll(['Authorization', 'Cookie']));
    });
  });

  group('runtime', () {
    setUp(() {
      runtime.applyConfig(const FalconerConfig());
    });

    test('applyConfig caches effectiveEnabled', () {
      runtime.applyConfig(const FalconerConfig(enabled: false));
      expect(runtime.captureEnabled, isFalse);
      runtime.applyConfig(const FalconerConfig(enabled: true));
      expect(runtime.captureEnabled, isTrue);
    });
  });
}
