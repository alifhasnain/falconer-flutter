#if DEBUG
import Foundation

/// The resolved configuration the native side holds. Mirrors Dart
/// `FalconerConfig.toMap()` (`ConfigKeys`) and Kotlin `FalconerNativeConfig`.
///
/// `enabled` is the already-resolved `effectiveEnabled` from Dart (after release
/// gating), so the native backstop drops log calls when capture is off even if a
/// stray payload arrives.
struct FalconerNativeConfig {
    var enabled: Bool
    var maxContentLength: Int
    /// Header names to mask, stored lowercased for case-insensitive matching.
    var redactHeaders: Set<String>
    var retention: RetentionWindow
    var showNotification: Bool

    /// Matches Dart `FalconerConfig`'s defaults (debug capture, 250 000-byte cap,
    /// one-day retention, the strong default redaction set).
    static let defaults = FalconerNativeConfig(
        enabled: true,
        maxContentLength: 250_000,
        redactHeaders: Set(
            ["Authorization", "Cookie", "Set-Cookie",
             "Proxy-Authorization", "X-Api-Key", "X-Auth-Token"]
                .map { $0.lowercased() }
        ),
        retention: .oneDay,
        showNotification: true
    )

    static func from(_ map: [String: Any]) -> FalconerNativeConfig {
        var config = FalconerNativeConfig.defaults
        if let enabled = PayloadMapper.present(map[ConfigKeys.enabled]) as? Bool {
            config.enabled = enabled
        }
        if let max = PayloadMapper.int(map[ConfigKeys.maxContentLength]) {
            config.maxContentLength = max
        }
        if let headers = PayloadMapper.present(map[ConfigKeys.redactHeaders]) as? [Any] {
            config.redactHeaders = Set(
                headers.compactMap { PayloadMapper.string($0)?.lowercased() }
            )
        }
        if let retention = PayloadMapper.string(map[ConfigKeys.retention]) {
            config.retention = RetentionWindow.from(key: retention)
        }
        if let show = PayloadMapper.present(map[ConfigKeys.showNotification]) as? Bool {
            config.showNotification = show
        }
        return config
    }
}
#endif
