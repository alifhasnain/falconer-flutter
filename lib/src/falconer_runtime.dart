// Internal runtime state shared across all FalconerInterceptor instances.
//
// `Falconer.configure` calls applyConfig, which caches the resolved enabled
// flag and the active config (redaction set + content cap) read on the
// interceptor hot path.
import 'package:flutter/foundation.dart';

import 'config/falconer_config.dart';

/// When `false`, the interceptor reads no bodies and sends no channel calls.
/// Initialized from the default config so a release build is inert before
/// `configure` is even called.
bool captureEnabled = const FalconerConfig().effectiveEnabled;

/// The active configuration the interceptor reads when building payloads.
FalconerConfig activeConfig = const FalconerConfig();

/// Whether the one-time release-capture warning has been emitted.
@visibleForTesting
bool releaseCaptureWarned = false;

/// Applies [config]: caches the enabled flag and the active config.
void applyConfig(FalconerConfig config) {
  activeConfig = config;
  captureEnabled = config.effectiveEnabled;
}

/// Emits a one-time warning when capture is active in a release build.
void maybeWarnReleaseCapture(FalconerConfig config, {required bool isRelease}) {
  if (isRelease && config.effectiveEnabled && !releaseCaptureWarned) {
    releaseCaptureWarned = true;
    debugPrint(
      'WARNING Falconer: HTTP capture is ENABLED in a RELEASE build. Captured '
      'requests and responses persist on this device. Ensure auth/PII headers '
      'are redacted and do NOT capture cardholder data (PCI-DSS).',
    );
  }
}
