#if DEBUG
import Foundation

/// Native re-application of redaction + truncation — a defense-in-depth backstop.
///
/// Dart already masks matched headers and truncates over-cap bodies before the
/// payload crosses the channel (secrets never reach here). These functions
/// re-apply the SAME rules on the native side so behaviour is identical to
/// Android regardless of platform, and so a payload that somehow skipped the
/// Dart pass is still guarded. Marker strings are byte-identical to
/// `transaction_dto.dart`.
enum Redactor {
    /// The mask substituted for redacted header values. Mirrors
    /// `FalconerConfig.redactedMarker`.
    static let redactedMarker = "**redacted**"

    /// Masks header values whose names match `redactHeaders` (case-insensitive).
    /// `redactHeaders` is expected pre-lowercased (see `FalconerNativeConfig`).
    static func redact(
        headers: [String: String],
        redactHeaders: Set<String>
    ) -> [String: String] {
        guard !redactHeaders.isEmpty else { return headers }
        var out: [String: String] = [:]
        for (key, value) in headers {
            out[key] = redactHeaders.contains(key.lowercased()) ? redactedMarker : value
        }
        return out
    }

    /// Truncates an over-cap body, appending a visible marker. `size` is the
    /// original byte size; the caller still reports it as the content length.
    /// Mirrors `_truncate` in `transaction_dto.dart`.
    static func truncate(body: String?, size: Int64?, maxContentLength: Int) -> String? {
        guard let body = body, let size = size, size > Int64(maxContentLength) else {
            return body
        }
        let max = maxContentLength
        let head = body.count > max ? String(body.prefix(max)) : body
        return "\(head)\n\n[Falconer: truncated — original \(size) bytes, showing first \(max)]"
    }
}
#endif
