import 'package:falconer/falconer.dart';
import 'package:falconer/src/falconer_runtime.dart' as runtime;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FalconerConfig', () {
    test('defaults', () {
      const c = FalconerConfig();
      expect(c.enableInReleaseBuilds, false);
      expect(c.maxContentLength, 250000);
      expect(c.retention, RetentionPeriod.oneDay);
      expect(c.showNotification, true);
      expect(c.redactHeaders, contains('Authorization'));
    });

    test('resolveEnabled gates release behind both flags', () {
      // Debug branch: enableInReleaseBuilds is ignored.
      expect(const FalconerConfig(enabled: true).resolveEnabled(false), isTrue);
      expect(
        const FalconerConfig(enabled: false).resolveEnabled(false),
        isFalse,
      );

      // Release branch: requires enabled AND enableInReleaseBuilds.
      expect(
        const FalconerConfig(
          enabled: true,
          enableInReleaseBuilds: false,
        ).resolveEnabled(true),
        isFalse,
      );
      expect(
        const FalconerConfig(
          enabled: true,
          enableInReleaseBuilds: true,
        ).resolveEnabled(true),
        isTrue,
      );
      expect(
        const FalconerConfig(
          enabled: false,
          enableInReleaseBuilds: true,
        ).resolveEnabled(true),
        isFalse,
      );
    });

    test('copyWith overrides only the given fields', () {
      const c = FalconerConfig();
      final c2 = c.copyWith(
        maxContentLength: 10,
        retention: RetentionPeriod.forever,
      );
      expect(c2.maxContentLength, 10);
      expect(c2.retention, RetentionPeriod.forever);
      expect(c2.enableInReleaseBuilds, c.enableInReleaseBuilds);
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
      runtime.releaseCaptureWarned = false;
      runtime.applyConfig(const FalconerConfig());
    });

    test('applyConfig caches effectiveEnabled', () {
      runtime.applyConfig(const FalconerConfig(enabled: false));
      expect(runtime.captureEnabled, isFalse);
      runtime.applyConfig(const FalconerConfig(enabled: true));
      expect(runtime.captureEnabled, isTrue);
    });

    test('maybeWarnReleaseCapture warns once', () {
      const c = FalconerConfig(enabled: true, enableInReleaseBuilds: true);
      runtime.maybeWarnReleaseCapture(c, isRelease: true);
      expect(runtime.releaseCaptureWarned, isTrue);
      runtime.maybeWarnReleaseCapture(c, isRelease: true); // no-op, no throw
      expect(runtime.releaseCaptureWarned, isTrue);
    });

    test('no release warning in debug', () {
      runtime.maybeWarnReleaseCapture(
        const FalconerConfig(enabled: true),
        isRelease: false,
      );
      expect(runtime.releaseCaptureWarned, isFalse);
    });
  });
}
