#if DEBUG
import Foundation

/// Retention window for stored transactions. Mirrors Dart `RetentionPeriod`
/// (`retention_period.dart`) and its wire keys.
enum RetentionWindow: String {
    case oneHour
    case oneDay
    case oneWeek
    case forever

    /// Retention duration in milliseconds, or `nil` for `forever`.
    var millis: Int64? {
        switch self {
        case .oneHour: return 60 * 60 * 1000
        case .oneDay: return 24 * 60 * 60 * 1000
        case .oneWeek: return 7 * 24 * 60 * 60 * 1000
        case .forever: return nil
        }
    }

    static func from(key: String?) -> RetentionWindow {
        guard let key = key, let value = RetentionWindow(rawValue: key) else {
            return .oneDay
        }
        return value
    }
}

/// The `logRequest` payload, parsed into typed fields.
struct RequestData {
    let id: String
    let startedAt: Int64
    let method: String
    let url: String
    let host: String
    let path: String
    let scheme: String
    let requestHeaders: [String: String]
    let requestContentType: String?
    let requestContentLength: Int64?
    let requestBody: String?
    let requestBodyKind: String
}

/// The `logResponse` payload, parsed into typed fields.
struct ResponseData {
    let id: String
    let completedAt: Int64
    let tookMs: Int64
    let statusCode: Int?
    let statusMessage: String?
    let protocolName: String?
    let responseHeaders: [String: String]
    let responseContentType: String?
    let responseContentLength: Int64?
    let responseBody: String?
    let responseBodyKind: String?
    let responseImageBytes: Data?
}

/// The `logError` payload (response-less transport failures).
struct ErrorData {
    let id: String
    let completedAt: Int64
    let tookMs: Int64
    let error: String
}

/// A stored transaction — the row shape persisted by the DAO and consumed by
/// the SwiftUI inspector. In-row `responseImageBytes` BLOB (mirrors the Android
/// `Transactions.sq` schema: image bytes stored in-row).
struct HttpTransaction: Identifiable, Equatable {
    let id: String
    var startedAt: Int64
    var method: String
    var url: String
    var host: String
    var path: String
    var scheme: String
    var requestHeaders: [String: String]
    var requestContentType: String?
    var requestContentLength: Int64?
    var requestBody: String?
    var requestBodyKind: String

    var completedAt: Int64?
    var tookMs: Int64?
    var statusCode: Int?
    var statusMessage: String?
    var protocolName: String?
    var responseHeaders: [String: String]
    var responseContentType: String?
    var responseContentLength: Int64?
    var responseBody: String?
    var responseBodyKind: String?
    var responseImageBytes: Data?

    var error: String?

    /// True once a response or error has merged onto the request.
    var isComplete: Bool { completedAt != nil }

    /// True when the transaction ended in a transport error (no response).
    var isFailure: Bool { error != nil }
}
#endif
