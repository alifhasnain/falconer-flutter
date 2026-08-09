#if DEBUG
import Foundation

/// Pure formatting + match-finding logic, kept free of SwiftUI so it is unit
/// testable (mirrors the Android split: match-finding is separated from the
/// `AnnotatedString` rendering, which is not JVM-safe there).
enum BodyFormatting {

    /// Pretty-prints a JSON string. Returns `nil` if the text is not valid JSON
    /// (the caller then shows it verbatim).
    static func prettyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(
                  with: data, options: [.fragmentsAllowed]
              ),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .withoutEscapingSlashes]
              ) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    /// Case-insensitive substring matches for search highlighting. Empty query
    /// or no matches → empty array.
    static func matchRanges(in haystack: String, query: String) -> [Range<String.Index>] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let found = haystack.range(
                  of: trimmed, options: .caseInsensitive,
                  range: searchStart..<haystack.endIndex
              ) {
            ranges.append(found)
            searchStart = found.upperBound > found.lowerBound ? found.upperBound : haystack.index(after: found.lowerBound)
        }
        return ranges
    }

    static func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes = bytes, bytes >= 0 else { return "—" }
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB"]
        var value = Double(bytes) / 1024
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: "%.1f %@", value, units[unit])
    }

    static func formatDuration(_ ms: Int64?) -> String {
        guard let ms = ms else { return "—" }
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.2f s", Double(ms) / 1000)
    }

    static func formatTimestamp(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
#endif
