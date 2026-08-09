#if DEBUG
import Foundation

/// Rebuilds an executable `curl` command for a transaction (mirrors Android's
/// `CurlBuilder`). Redacted header values are carried through verbatim — the
/// mask (`**redacted**`) travels, the real secret never did.
enum CurlBuilder {
    static func build(_ tx: HttpTransaction) -> String {
        var parts: [String] = ["curl -X \(tx.method) '\(escape(tx.url))'"]
        for (key, value) in tx.requestHeaders.sorted(by: { $0.key < $1.key }) {
            parts.append("-H '\(escape("\(key): \(value)"))'")
        }
        if let body = tx.requestBody, !body.isEmpty,
           tx.requestBodyKind != BodyKinds.none,
           tx.requestBodyKind != BodyKinds.image,
           tx.requestBodyKind != BodyKinds.unsupported {
            parts.append("--data '\(escape(body))'")
        }
        return parts.joined(separator: " \\\n  ")
    }

    /// POSIX single-quote escaping: close, escaped quote, reopen.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }
}
#endif
