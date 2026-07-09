import 'package:flutter/foundation.dart';

import '../platform/contract.dart';
import 'retention_period.dart';

/// Immutable Falconer configuration. Pass once to `Falconer.configure`.
///
/// ## Security (PCI / payment-gateway context)
///
/// Falconer persists captured HTTP data **on-device**. To protect secrets:
///
/// - Capture is **off in release builds by default**. It activates only when
///   both [enabled] and [enableInReleaseBuilds] are `true`.
/// - Headers named in [redactHeaders] are masked **in Dart, before the payload
///   crosses the channel** — secrets never reach native logs or the database.
/// - Bodies/images larger than [maxContentLength] are truncated (the original
///   size is still reported).
///
/// **Do not capture cardholder data (PAN/CVV) or other regulated PII.** Exclude
/// such endpoints from capture and keep release capture disabled. Body-content
/// redaction patterns are future work (see `doc/PLAN.md`).
@immutable
class FalconerConfig {
  const FalconerConfig({
    this.enabled = kDebugMode,
    this.enableInReleaseBuilds = false,
    this.redactHeaders = defaultRedactHeaders,
    this.maxContentLength = 250000,
    this.retention = RetentionPeriod.oneDay,
    this.showNotification = true,
  });

  /// Master switch. Defaults to `kDebugMode` (on in debug, off in release).
  final bool enabled;

  /// Guard for release builds. Capture in release requires this **and**
  /// [enabled] to be `true`.
  final bool enableInReleaseBuilds;

  /// Header names masked before capture (case-insensitive).
  final Set<String> redactHeaders;

  /// Bodies/images larger than this (bytes) are truncated.
  final int maxContentLength;

  /// Retention window for stored transactions.
  final RetentionPeriod retention;

  /// Whether the native ongoing notification is shown.
  final bool showNotification;

  /// Strong default redaction set for common auth/session headers.
  static const Set<String> defaultRedactHeaders = {
    'Authorization',
    'Cookie',
    'Set-Cookie',
    'Proxy-Authorization',
    'X-Api-Key',
    'X-Auth-Token',
  };

  /// The mask substituted for redacted header values.
  static const String redactedMarker = '**redacted**';

  /// Whether capture is actually active, after release gating.
  bool get effectiveEnabled => resolveEnabled(kReleaseMode);

  /// Pure resolution of [effectiveEnabled]; [isReleaseMode] injected for tests.
  @visibleForTesting
  bool resolveEnabled(bool isReleaseMode) =>
      enabled && (isReleaseMode ? enableInReleaseBuilds : true);

  FalconerConfig copyWith({
    bool? enabled,
    bool? enableInReleaseBuilds,
    Set<String>? redactHeaders,
    int? maxContentLength,
    RetentionPeriod? retention,
    bool? showNotification,
  }) {
    return FalconerConfig(
      enabled: enabled ?? this.enabled,
      enableInReleaseBuilds:
          enableInReleaseBuilds ?? this.enableInReleaseBuilds,
      redactHeaders: redactHeaders ?? this.redactHeaders,
      maxContentLength: maxContentLength ?? this.maxContentLength,
      retention: retention ?? this.retention,
      showNotification: showNotification ?? this.showNotification,
    );
  }

  /// The wire form sent to the native side (defense-in-depth backstop).
  /// Sends the **resolved** [effectiveEnabled] so native knows the live state.
  Map<String, dynamic> toMap() => <String, dynamic>{
    ConfigKeys.enabled: effectiveEnabled,
    ConfigKeys.maxContentLength: maxContentLength,
    ConfigKeys.redactHeaders: redactHeaders.toList(),
    ConfigKeys.retention: retention.key,
    ConfigKeys.showNotification: showNotification,
  };
}
