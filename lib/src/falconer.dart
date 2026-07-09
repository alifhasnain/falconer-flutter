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
  /// interceptor, warns once if capture is active in a release build, then
  /// forwards the config to the native backstop.
  static Future<void> configure([
    FalconerConfig config = const FalconerConfig(),
  ]) {
    runtime.applyConfig(config);
    runtime.maybeWarnReleaseCapture(config, isRelease: kReleaseMode);
    return FalconerPlatform.instance.configure(config.toMap());
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
