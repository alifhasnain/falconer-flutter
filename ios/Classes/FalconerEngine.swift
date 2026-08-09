import Foundation

/// The engine seam — the iOS mirror of Kotlin's `FalconerEngine` interface.
///
/// The thin `FalconerPlugin` references ONLY this protocol; it never names a
/// concrete implementation except at the single `#if DEBUG` selection point.
/// That keeps a release build free of any compile edge to the inspector, so the
/// real engine (and everything it pulls in) is absent from the release binary.
///
/// Two implementations exist:
///   Debug   -> RealFalconerEngine (SwiftUI UI + SQLite storage + capture)
///   Release -> NoOpFalconerEngine (inert; `observeCount` yields 0 once)
///
/// All arguments are the raw channel maps (`[String: Any]`); parsing happens
/// inside the engine so the plugin stays free of capture concerns.
protocol FalconerEngine {
    /// Bind the engine to the app lifecycle (open storage, run retention, …).
    func attach()

    /// Release resources; stop observers.
    func detach()

    /// Apply the resolved configuration map (`ConfigKeys`).
    func configure(_ args: [String: Any])

    /// Record a request as it is sent (two-phase logging).
    func logRequest(_ args: [String: Any])

    /// Record a completed response, merged onto the matching request by id.
    func logResponse(_ args: [String: Any])

    /// Record a response-less transport failure, merged by id.
    func logError(_ args: [String: Any])

    /// Clear all captured transactions and dismiss any open inspector.
    func clear()

    /// Present the native inspection UI over the current app screen.
    func launchUi()

    /// Live count of stored transactions. Yields the current value on
    /// subscription and after every insert/clear.
    func observeCount() -> AsyncStream<Int>
}
