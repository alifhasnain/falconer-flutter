import Foundation

/// The inert engine linked in release builds.
///
/// Every method is a no-op; `observeCount` yields a single `0` and completes.
/// This is the ONLY `FalconerEngine` that compiles when `DEBUG` is undefined, so
/// a release binary contains no capture, no storage, and no UI — the inspector
/// is physically absent (Method A, mirrors Android's `falconer-noop`).
final class NoOpFalconerEngine: FalconerEngine {
    func attach() {}
    func detach() {}
    func configure(_ args: [String: Any]) {}
    func logRequest(_ args: [String: Any]) {}
    func logResponse(_ args: [String: Any]) {}
    func logError(_ args: [String: Any]) {}
    func clear() {}
    func launchUi() {}

    func observeCount() -> AsyncStream<Int> {
        AsyncStream { continuation in
            continuation.yield(0)
            continuation.finish()
        }
    }
}
