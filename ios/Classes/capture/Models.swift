#if DEBUG
import Foundation

/// Retention window for stored transactions. Mirrors Dart `RetentionPeriod`
/// (`retention_period.dart`) and its wire keys — the raw values ARE those keys.
///
/// Every window is bounded; `oneMonth` is the ceiling. There is deliberately no
/// "keep forever": captured traffic is unredacted-by-default payload sitting in
/// an on-device SQLite file, so an unbounded window would let a debug build
/// accumulate request and response bodies indefinitely.
///
/// Rolling durations measured back from now, not calendar units: `oneMonth` is a
/// fixed 30 days. Adding a case here without adding it to Dart and Kotlin means
/// the other sides fall back to one day silently (`from(key:)` below does the
/// same in reverse).
/// `CaseIterable` so the Swift golden test can pin the whole wire-key set.
enum RetentionWindow: String, CaseIterable {
    case oneHour
    case oneDay
    case oneWeek
    case oneMonth

    /// Retention duration in milliseconds.
    var millis: Int64 {
        switch self {
        case .oneHour: return 60 * 60 * 1000
        case .oneDay: return 24 * 60 * 60 * 1000
        case .oneWeek: return 7 * 24 * 60 * 60 * 1000
        case .oneMonth: return 30 * 24 * 60 * 60 * 1000
        }
    }

    /// Unknown keys fall back to one day. The retired `"forever"` key lands here
    /// too — an older host app degrades to a one-day window, which deletes more,
    /// not less.
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

/// The narrow projection behind the inspector's list screen.
///
/// Everything the list renders, and nothing else — no headers, no request or
/// response body, no image BLOB. `HttpTransaction` stays the full row and is read
/// one at a time by the detail screen, which is the only place that actually
/// shows a payload.
///
/// The list query re-runs on every write, so keeping bodies out of it is what
/// stops a busy session from re-reading hundreds of kilobytes per transaction to
/// draw seven short fields. Mirrors Android's `TransactionListRow`.
struct TransactionListRow: Identifiable, Equatable {
    let id: String
    var startedAt: Int64
    var tookMs: Int64?
    var method: String
    /// Kept in the projection: the list falls back to the full URL when `path` is
    /// empty, and the in-memory filter matches on it.
    var url: String
    var host: String
    var path: String
    var statusCode: Int?
    var responseContentLength: Int64?
    var error: String?

    /// True when the transaction ended in a transport error (no response).
    var isFailure: Bool { error != nil }
}
#endif
