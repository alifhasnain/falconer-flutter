#if DEBUG
import Combine
import Foundation

/// The repository + observable state at the heart of the debug engine.
///
/// - Serializes all SQLite access on one serial queue (single-connection model).
/// - Applies the redaction/truncation backstop before persisting.
/// - Republishes `transactions` on the main actor for the SwiftUI inspector.
/// - Feeds `observeCount()` as an `AsyncStream<Int>` for the EventChannel.
///
/// Insert-on-request, merge-on-response|error uses read-modify-write (data
/// volumes are tiny), so the DAO stays a plain upsert + queries.
final class TransactionStore: ObservableObject {
    /// Reverse-chronological list for the inspector. Main-actor published.
    @Published private(set) var transactions: [HttpTransaction] = []

    private let queue = DispatchQueue(label: "dev.alifhasnain.falconer.db")
    private let dao: HttpTransactionDao?
    private let retention: RetentionManager?
    private var config = FalconerNativeConfig.defaults

    private let countLock = NSLock()
    private var currentCount = 0
    private var countContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    init() {
        if let dao = TransactionStore.openDao() {
            self.dao = dao
            self.retention = RetentionManager(dao: dao)
        } else {
            self.dao = nil
            self.retention = nil
        }
        queue.async { [weak self] in self?.reloadAndPublish() }
    }

    private static func openDao() -> HttpTransactionDao? {
        let fm = FileManager.default
        guard let dir = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        let path = dir.appendingPathComponent("falconer.db").path
        guard let db = try? SQLiteDatabase(path: path),
              let dao = try? HttpTransactionDao(db: db) else { return nil }
        return dao
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Configure

    func configure(_ map: [String: Any]) {
        let parsed = FalconerNativeConfig.from(map)
        queue.async { [weak self] in
            guard let self = self else { return }
            self.config = parsed
            self.retention?.update(window: parsed.retention)
            self.retention?.cleanupNow(now: TransactionStore.nowMs())
            self.reloadAndPublish()
        }
    }

    // MARK: - Ingest

    func ingestRequest(_ map: [String: Any]) {
        guard let data = PayloadMapper.request(map) else { return }
        queue.async { [weak self] in
            guard let self = self, self.config.enabled, let dao = self.dao else { return }
            let tx = self.makeTransaction(from: data)
            try? dao.upsert(tx)
            self.afterWrite()
        }
    }

    func ingestResponse(_ map: [String: Any]) {
        guard let data = PayloadMapper.response(map) else { return }
        queue.async { [weak self] in
            guard let self = self, self.config.enabled, let dao = self.dao else { return }
            var tx = (try? dao.byId(data.id)) ?? self.placeholder(id: data.id)
            self.applyResponse(data, to: &tx)
            try? dao.upsert(tx)
            self.afterWrite()
        }
    }

    func ingestError(_ map: [String: Any]) {
        guard let data = PayloadMapper.error(map) else { return }
        queue.async { [weak self] in
            guard let self = self, self.config.enabled, let dao = self.dao else { return }
            var tx = (try? dao.byId(data.id)) ?? self.placeholder(id: data.id)
            tx.completedAt = data.completedAt
            tx.tookMs = data.tookMs
            tx.error = data.error
            try? dao.upsert(tx)
            self.afterWrite()
        }
    }

    func clear() {
        queue.async { [weak self] in
            guard let self = self else { return }
            try? self.dao?.clear()
            self.reloadAndPublish()
        }
    }

    // MARK: - Live count

    func observeCount() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            self.countLock.lock()
            self.countContinuations[id] = continuation
            let snapshot = self.currentCount
            self.countLock.unlock()
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                self?.countLock.lock()
                self?.countContinuations[id] = nil
                self?.countLock.unlock()
            }
        }
    }

    // MARK: - Internals

    private func afterWrite() {
        retention?.cleanupThrottled(now: TransactionStore.nowMs())
        reloadAndPublish()
    }

    /// Must run on `queue`. Reloads the list + count and republishes.
    private func reloadAndPublish() {
        let rows = (try? dao?.all()) ?? []
        let count = rows.count
        countLock.lock()
        currentCount = count
        let continuations = Array(countContinuations.values)
        countLock.unlock()
        for continuation in continuations { continuation.yield(count) }
        DispatchQueue.main.async { [weak self] in
            self?.transactions = rows
        }
    }

    private func placeholder(id: String) -> HttpTransaction {
        HttpTransaction(
            id: id, startedAt: 0, method: "", url: "", host: "", path: "", scheme: "",
            requestHeaders: [:], requestContentType: nil, requestContentLength: nil,
            requestBody: nil, requestBodyKind: BodyKinds.none,
            completedAt: nil, tookMs: nil, statusCode: nil, statusMessage: nil,
            protocolName: nil, responseHeaders: [:], responseContentType: nil,
            responseContentLength: nil, responseBody: nil, responseBodyKind: nil,
            responseImageBytes: nil, error: nil
        )
    }

    private func makeTransaction(from d: RequestData) -> HttpTransaction {
        HttpTransaction(
            id: d.id,
            startedAt: d.startedAt,
            method: d.method,
            url: d.url,
            host: d.host,
            path: d.path,
            scheme: d.scheme,
            requestHeaders: Redactor.redact(headers: d.requestHeaders, redactHeaders: config.redactHeaders),
            requestContentType: d.requestContentType,
            requestContentLength: d.requestContentLength,
            requestBody: Redactor.truncate(body: d.requestBody, size: d.requestContentLength, maxContentLength: config.maxContentLength),
            requestBodyKind: d.requestBodyKind,
            completedAt: nil, tookMs: nil, statusCode: nil, statusMessage: nil,
            protocolName: nil, responseHeaders: [:], responseContentType: nil,
            responseContentLength: nil, responseBody: nil, responseBodyKind: nil,
            responseImageBytes: nil, error: nil
        )
    }

    private func applyResponse(_ d: ResponseData, to tx: inout HttpTransaction) {
        tx.completedAt = d.completedAt
        tx.tookMs = d.tookMs
        tx.statusCode = d.statusCode
        tx.statusMessage = d.statusMessage
        tx.protocolName = d.protocolName
        tx.responseHeaders = Redactor.redact(headers: d.responseHeaders, redactHeaders: config.redactHeaders)
        tx.responseContentType = d.responseContentType
        tx.responseContentLength = d.responseContentLength
        tx.responseBodyKind = d.responseBodyKind

        // Image over the cap: drop the bytes and mark it (mirrors Dart).
        if d.responseBodyKind == BodyKinds.image, let bytes = d.responseImageBytes {
            if bytes.count > config.maxContentLength {
                tx.responseImageBytes = nil
                tx.responseBody =
                    "[Falconer: image truncated — \(bytes.count) bytes > \(config.maxContentLength)]"
            } else {
                tx.responseImageBytes = bytes
                tx.responseBody = nil
            }
        } else {
            tx.responseImageBytes = nil
            tx.responseBody = Redactor.truncate(
                body: d.responseBody, size: d.responseContentLength,
                maxContentLength: config.maxContentLength
            )
        }
    }
}
#endif
