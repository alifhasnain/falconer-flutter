import 'package:flutter/foundation.dart';

import 'config/falconer_config.dart';
import 'falconer_runtime.dart' as runtime;
import 'platform/falconer_platform.dart';

/// The public entry point to Falconer.
///
/// A thin, platform-agnostic facade over [FalconerPlatform]. The log* methods
/// are intentionally not exposed here — they are called by `FalconerInterceptor`,
/// not by host apps.
class Falconer {
  Falconer._();

  /// Round-trips the platform channel; returns `"pong"`. Diagnostic only.
  static Future<String?> ping() => FalconerPlatform.instance.ping();

  /// Configures Falconer. Call once at startup, before requests fire.
  ///
  /// Caches the resolved enabled flag and redaction/truncation settings for the
  /// interceptor, then forwards the config to the native backstop. In a release
  /// build the resolved state is always disabled, so this is a cheap no-op.
  ///
  /// **Never throws.** A diagnostic tool must not be able to break the host app,
  /// so a failing platform channel is swallowed and reported via [debugPrint] —
  /// the same policy the log calls already use. The Dart-side configuration is
  /// applied before the channel call, so capture still honours [config] even if
  /// the channel is unavailable; only the native backstop misses the update and
  /// keeps its own conservative defaults.
  ///
  /// Note this needs a live binding. Calling it as the first statement of `main`
  /// requires `WidgetsFlutterBinding.ensureInitialized()` first.
  static Future<void> configure([
    FalconerConfig config = const FalconerConfig(),
  ]) async {
    runtime.applyConfig(config);
    try {
      await FalconerPlatform.instance.configure(config.toMap());
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Falconer: configure could not reach the platform channel ($error). '
          'Dart-side capture is configured, but the native side keeps its own '
          'defaults — so headers may still be masked with the default redaction '
          'set and swept on the default retention window. If this happened at '
          'startup, call WidgetsFlutterBinding.ensureInitialized() before '
          'Falconer.configure().',
        );
      }
    }
  }

  /// Whether capture is currently active (after release gating).
  static bool get effectiveEnabled => runtime.captureEnabled;

  /// Launches the native inspection UI.
  static Future<void> launchUi() => FalconerPlatform.instance.launchUi();

  /// Clears all captured transactions.
  static Future<void> clear() => FalconerPlatform.instance.clearTransactions();

  /// Requests the Android 13+ notification permission. Returns the grant result.
  static Future<bool> requestNotificationPermission() =>
      FalconerPlatform.instance.requestNotificationPermission();

  /// Live count of captured transactions.
  static Stream<int> get transactionCount =>
      FalconerPlatform.instance.transactionCount;
}
