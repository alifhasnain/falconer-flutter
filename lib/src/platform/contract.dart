/// The frozen Dart <-> native channel contract.
///
/// Method names, channel names and payload field keys live here as the single
/// Dart-side source of truth. They are mirrored in
/// `android/.../channel/MethodNames.kt` and `PayloadKeys.kt`, and documented in
/// `doc/CHANNEL_CONTRACT.md`.
///
/// Changing any value here is a breaking contract change: update the Kotlin
/// mirror, the doc, and the golden tests on both sides together. The golden
/// tests (`test/contract/contract_test.dart` and `PayloadMapperTest.kt`) fail
/// if a field is renamed, removed, or added on only one side.
library;

/// Platform channel names.
class FalconerChannels {
  FalconerChannels._();

  /// MethodChannel name.
  static const String method = 'falconer';

  /// EventChannel carrying the live transaction count (int stream).
  static const String transactionCountEvent = 'falconer/transactionCount';
}

/// MethodChannel method names.
class FalconerMethods {
  FalconerMethods._();

  static const String ping = 'ping';
  static const String configure = 'configure';
  static const String logRequest = 'logRequest';
  static const String logResponse = 'logResponse';
  static const String logError = 'logError';
  static const String clearTransactions = 'clearTransactions';
  static const String launchUi = 'launchUi';
  static const String requestNotificationPermission =
      'requestNotificationPermission';
}

/// Payload map field keys, shared across `logRequest` / `logResponse` /
/// `logError`.
class PayloadKeys {
  PayloadKeys._();

  // Shared.
  static const String id = 'id';

  // logRequest.
  static const String startedAt = 'startedAt';
  static const String method = 'method';
  static const String url = 'url';
  static const String host = 'host';
  static const String path = 'path';
  static const String scheme = 'scheme';
  static const String requestHeaders = 'requestHeaders';
  static const String requestContentType = 'requestContentType';
  static const String requestContentLength = 'requestContentLength';
  static const String requestBody = 'requestBody';
  static const String requestBodyKind = 'requestBodyKind';

  // logResponse.
  static const String completedAt = 'completedAt';
  static const String tookMs = 'tookMs';
  static const String statusCode = 'statusCode';
  static const String statusMessage = 'statusMessage';
  static const String protocol = 'protocol';
  static const String responseHeaders = 'responseHeaders';
  static const String responseContentType = 'responseContentType';
  static const String responseContentLength = 'responseContentLength';
  static const String responseBody = 'responseBody';
  static const String responseBodyKind = 'responseBodyKind';
  static const String responseImageBytes = 'responseImageBytes';

  // logError.
  static const String error = 'error';
}

/// `configure` map field keys (Phase 7 schema).
class ConfigKeys {
  ConfigKeys._();

  static const String enabled = 'enabled';
  static const String maxContentLength = 'maxContentLength';
  static const String redactHeaders = 'redactHeaders';
  static const String retention = 'retention';
  static const String showNotification = 'showNotification';
}

/// `requestBodyKind` / `responseBodyKind` wire values (produced by `body_codec`).
class BodyKinds {
  BodyKinds._();

  static const String none = 'none';
  static const String text = 'text';
  static const String json = 'json';
  static const String multipart = 'multipart';
  static const String image = 'image';
  static const String unsupported = 'unsupported';
}
