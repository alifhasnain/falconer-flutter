import 'package:flutter/foundation.dart';

import '../capture/body_decoder.dart';
import '../platform/contract.dart';
import 'retention_period.dart';

/// Immutable Falconer configuration. Pass once to `Falconer.configure`.
///
/// ## Security (PCI / payment-gateway context)
///
/// Falconer persists captured HTTP data **on-device**. To protect secrets:
///
/// - Capture is **impossible in release builds**. [resolveEnabled] returns
///   `false` whenever `kReleaseMode` is set, so no configuration — including
///   `enabled: true` — can turn capture on in a release build.
/// - Headers named in [redactHeaders] are masked **in Dart, before the payload
///   crosses the channel** — secrets never reach native logs or the database.
/// - Bodies/images larger than [maxContentLength] are truncated (the original
///   size is still reported).
///
/// **Do not capture cardholder data (PAN/CVV) or other regulated PII.** Exclude
/// such endpoints from capture — set `FalconerExtras.skipCapture` on the
/// request's `extra` map. Only header *names* are redacted — body-content
/// redaction is not implemented, so a PAN inside a JSON body would be stored
/// verbatim in a debug build.
///
/// [bodyDecoders] make that last point sharper: an app whose payloads are
/// encrypted on the wire currently stores ciphertext, and a decoder replaces it
/// with plaintext. Registering one is a deliberate decision to keep readable
/// payment traffic on the device for the length of the [retention] window.
///
/// Falconer has no remote/network sink: captured data never leaves the device.
@immutable
class FalconerConfig {
  const FalconerConfig({
    this.enabled = kDebugMode,
    this.redactHeaders = defaultRedactHeaders,
    this.maxContentLength = 250000,
    this.retention = RetentionPeriod.oneWeek,
    this.showNotification = true,
    this.bodyDecoders = const [],
  });

  /// Master switch, honoured in debug builds only. Defaults to `kDebugMode`.
  ///
  /// Setting this `true` does **not** enable capture in a release build — see
  /// [resolveEnabled].
  final bool enabled;

  /// Header names masked before capture (case-insensitive).
  final Set<String> redactHeaders;

  /// Bodies/images larger than this (bytes) are truncated.
  final int maxContentLength;

  /// Retention window for stored transactions. Defaults to
  /// [RetentionPeriod.oneWeek].
  ///
  /// This is the window in which captured payloads remain readable on the
  /// device, so prefer the shortest one that is still useful for debugging.
  /// Sweeps are time-based only — there is no row or size cap, and response
  /// images are stored in-row, so a long window on a busy app grows the store
  /// without bound.
  final RetentionPeriod retention;

  /// Whether the native ongoing notification is shown.
  final bool showNotification;

  /// Decoders applied to captured bodies, in order. The first non-null result
  /// wins; if every decoder declines, the raw captured body is stored.
  ///
  /// Dart-side only — decoders never cross the platform channel and are absent
  /// from [toMap]. See [FalconerBodyDecoder] for the security implications of
  /// writing decoded plaintext into the on-device store.
  final List<FalconerBodyDecoder> bodyDecoders;

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
  ///
  /// Release builds always resolve to `false`: capture is a debug-build
  /// capability, and the native engine is absent from release binaries anyway
  /// (Method A).
  @visibleForTesting
  bool resolveEnabled(bool isReleaseMode) => enabled && !isReleaseMode;

  FalconerConfig copyWith({
    bool? enabled,
    Set<String>? redactHeaders,
    int? maxContentLength,
    RetentionPeriod? retention,
    bool? showNotification,
    List<FalconerBodyDecoder>? bodyDecoders,
  }) {
    return FalconerConfig(
      enabled: enabled ?? this.enabled,
      redactHeaders: redactHeaders ?? this.redactHeaders,
      maxContentLength: maxContentLength ?? this.maxContentLength,
      retention: retention ?? this.retention,
      showNotification: showNotification ?? this.showNotification,
      bodyDecoders: bodyDecoders ?? this.bodyDecoders,
    );
  }

  /// The wire form sent to the native side (defense-in-depth backstop).
  /// Sends the **resolved** [effectiveEnabled] so native knows the live state.
  ///
  /// [bodyDecoders] is deliberately absent: only primitives cross the channel,
  /// and decoding happens entirely in Dart before the payload is built.
  Map<String, dynamic> toMap() => <String, dynamic>{
    ConfigKeys.enabled: effectiveEnabled,
    ConfigKeys.maxContentLength: maxContentLength,
    ConfigKeys.redactHeaders: redactHeaders.toList(),
    ConfigKeys.retention: retention.key,
    ConfigKeys.showNotification: showNotification,
  };
}
