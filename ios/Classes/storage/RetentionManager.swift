#if DEBUG
import Foundation

/// Deletes transactions older than the configured window. Runs once at startup
/// (after `configure`) and throttled on writes, mirroring the Android windows
/// (`oneHour` / `oneDay` / `oneWeek` / `forever`). `forever` never deletes.
final class RetentionManager {
    private let dao: HttpTransactionDao
    private var window: RetentionWindow = .oneDay
    private var lastRunMs: Int64 = 0

    /// At most one on-write sweep per minute; startup sweeps are unthrottled.
    private let throttleMs: Int64 = 60_000

    init(dao: HttpTransactionDao) {
        self.dao = dao
    }

    func update(window: RetentionWindow) {
        self.window = window
    }

    /// Unconditional sweep (call after `configure`).
    func cleanupNow(now: Int64) {
        guard let span = window.millis else { return }
        lastRunMs = now
        try? dao.deleteOlderThan(now - span)
    }

    /// Throttled sweep for the write path.
    func cleanupThrottled(now: Int64) {
        guard window.millis != nil else { return }
        if now - lastRunMs < throttleMs { return }
        cleanupNow(now: now)
    }
}
#endif
