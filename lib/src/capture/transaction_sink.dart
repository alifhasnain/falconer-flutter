import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/falconer_platform.dart';

/// The destination for captured transaction payloads.
///
/// All [FalconerInterceptor] instances share one sink, so traffic from many
/// Dio clients lands in a single store. Injectable for testing.
abstract class FalconerSink {
  void logRequest(Map<String, dynamic> data);
  void logResponse(Map<String, dynamic> data);
  void logError(Map<String, dynamic> data);
}

/// Default sink — forwards to [FalconerPlatform] fire-and-forget (D, Phase 3).
///
/// Log calls are not awaited so HTTP latency is untouched, and channel errors
/// are swallowed (logged in debug) so they never surface in the Dio chain.
class PlatformSink implements FalconerSink {
  const PlatformSink();

  @override
  void logRequest(Map<String, dynamic> data) =>
      _fire(() => FalconerPlatform.instance.logRequest(data));

  @override
  void logResponse(Map<String, dynamic> data) =>
      _fire(() => FalconerPlatform.instance.logResponse(data));

  @override
  void logError(Map<String, dynamic> data) =>
      _fire(() => FalconerPlatform.instance.logError(data));

  void _fire(Future<void> Function() op) {
    unawaited(
      Future<void>(op).catchError((Object error) {
        if (kDebugMode) {
          debugPrint('Falconer: channel log failed: $error');
        }
      }),
    );
  }
}
