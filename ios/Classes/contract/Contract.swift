import Foundation

/// The frozen Dart <-> native channel contract, mirrored for iOS.
///
/// The single Dart source of truth is `lib/src/platform/contract.dart`; the
/// Kotlin mirror lives in `android/.../channel/`. Changing any value here is a
/// breaking contract change — update the Dart source, the Kotlin mirror, the
/// doc (`doc/CHANNEL_CONTRACT.md`) and the golden tests on every side together.
///
/// These constants compile in ALL build configurations (the thin plugin needs
/// them); nothing inspector-specific lives here.

enum FalconerChannels {
    /// MethodChannel name.
    static let method = "falconer"
    /// EventChannel carrying the live transaction count (int stream).
    static let transactionCountEvent = "falconer/transactionCount"
}

enum FalconerMethods {
    static let ping = "ping"
    static let configure = "configure"
    static let logRequest = "logRequest"
    static let logResponse = "logResponse"
    static let logError = "logError"
    static let clearTransactions = "clearTransactions"
    static let launchUi = "launchUi"
    static let requestNotificationPermission = "requestNotificationPermission"
}

/// Payload map field keys, shared across logRequest / logResponse / logError.
enum PayloadKeys {
    // Shared.
    static let id = "id"

    // logRequest.
    static let startedAt = "startedAt"
    static let method = "method"
    static let url = "url"
    static let host = "host"
    static let path = "path"
    static let scheme = "scheme"
    static let requestHeaders = "requestHeaders"
    static let requestContentType = "requestContentType"
    static let requestContentLength = "requestContentLength"
    static let requestBody = "requestBody"
    static let requestBodyKind = "requestBodyKind"

    // logResponse.
    static let completedAt = "completedAt"
    static let tookMs = "tookMs"
    static let statusCode = "statusCode"
    static let statusMessage = "statusMessage"
    static let protocolName = "protocol"
    static let responseHeaders = "responseHeaders"
    static let responseContentType = "responseContentType"
    static let responseContentLength = "responseContentLength"
    static let responseBody = "responseBody"
    static let responseBodyKind = "responseBodyKind"
    static let responseImageBytes = "responseImageBytes"

    // logError.
    static let error = "error"
}

/// `configure` map field keys.
enum ConfigKeys {
    static let enabled = "enabled"
    static let maxContentLength = "maxContentLength"
    static let redactHeaders = "redactHeaders"
    static let retention = "retention"
    static let showNotification = "showNotification"
}

/// `requestBodyKind` / `responseBodyKind` wire values (produced by `body_codec`).
enum BodyKinds {
    static let none = "none"
    static let text = "text"
    static let json = "json"
    static let multipart = "multipart"
    static let image = "image"
    static let unsupported = "unsupported"
}
