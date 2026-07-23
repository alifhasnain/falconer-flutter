#if DEBUG
import Foundation

/// Renders a transaction as a shareable plain-text report (mirrors Android's
/// text export). Faithful to what was captured — truncation/redaction markers
/// travel through unchanged.
enum TextExporter {
    static func export(_ tx: HttpTransaction) -> String {
        var out = ""
        out += "\(tx.method) \(tx.url)\n"
        if let status = tx.statusCode {
            out += "Status: \(status)\(tx.statusMessage.map { " \($0)" } ?? "")\n"
        } else if let error = tx.error {
            out += "Error: \(error)\n"
        } else {
            out += "Status: (in flight)\n"
        }
        out += "Started: \(BodyFormatting.formatTimestamp(tx.startedAt))"
        out += "  ·  Took: \(BodyFormatting.formatDuration(tx.tookMs))\n"

        out += "\n── Request ──\n"
        out += headerBlock(tx.requestHeaders)
        if let body = tx.requestBody, !body.isEmpty {
            out += "\n\(body)\n"
        }

        out += "\n── Response ──\n"
        out += headerBlock(tx.responseHeaders)
        if let body = tx.responseBody, !body.isEmpty {
            out += "\n\(body)\n"
        } else if tx.responseBodyKind == BodyKinds.image {
            let size = Int64(tx.responseImageBytes?.count ?? 0)
            out += "\n[image · \(BodyFormatting.formatBytes(size))]\n"
        }
        return out
    }

    private static func headerBlock(_ headers: [String: String]) -> String {
        guard !headers.isEmpty else { return "(no headers)\n" }
        return headers.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n") + "\n"
    }
}
#endif
