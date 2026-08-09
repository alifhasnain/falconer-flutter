#if DEBUG
import SwiftUI

/// A quiet, composed identity — not raw SwiftUI/UIKit default (PRODUCT.md
/// principle 5). Chrome recedes; the payload is loudest (principle 1). System
/// semantic colors give correct light/dark contrast (≥4.5:1 for body text)
/// essentially for free.
enum FalconerTheme {
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    static let separator = Color(.separator)

    /// Accent used sparingly — search highlight, active tab underline.
    static let highlight = Color.yellow.opacity(0.45)

    /// Monospaced payload font — payloads read as data, not prose.
    static let mono = Font.system(.footnote, design: .monospaced)
    static let monoSmall = Font.system(.caption2, design: .monospaced)

    /// Restrained, legible method coloring.
    static func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return Color(red: 0.20, green: 0.55, blue: 0.35)
        case "POST": return Color(red: 0.18, green: 0.42, blue: 0.75)
        case "PUT", "PATCH": return Color(red: 0.72, green: 0.47, blue: 0.10)
        case "DELETE": return Color(red: 0.72, green: 0.24, blue: 0.24)
        default: return textSecondary
        }
    }

    /// Status coloring by class; nil (in-flight) reads as tertiary.
    static func statusColor(_ code: Int?) -> Color {
        guard let code = code else { return textTertiary }
        switch code {
        case 200..<300: return Color(red: 0.20, green: 0.55, blue: 0.35)
        case 300..<400: return Color(red: 0.18, green: 0.42, blue: 0.75)
        case 400..<500: return Color(red: 0.72, green: 0.47, blue: 0.10)
        default: return Color(red: 0.72, green: 0.24, blue: 0.24)
        }
    }
}
#endif
