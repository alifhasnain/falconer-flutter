#if DEBUG
import Foundation

/// Data-access for stored transactions over the `libsqlite3` wrapper.
///
/// Schema mirrors the Android `Transactions.sq` in-row shape (headers as JSON
/// text, response image bytes as an in-row BLOB). All access must be serialized
/// by the caller (`TransactionStore` uses a single serial queue), matching the
/// single-connection model.
final class HttpTransactionDao {
    private let db: SQLiteDatabase

    /// Column list — the mapper below reads by these 0-based indices, so this
    /// order and `map(_:)` must change together.
    private static let columns = """
    id, startedAt, method, url, host, path, scheme, \
    requestHeaders, requestContentType, requestContentLength, requestBody, requestBodyKind, \
    completedAt, tookMs, statusCode, statusMessage, protocolName, \
    responseHeaders, responseContentType, responseContentLength, responseBody, responseBodyKind, responseImageBytes, \
    error
    """

    init(db: SQLiteDatabase) throws {
        self.db = db
        try createSchema()
    }

    private func createSchema() throws {
        try db.execute("PRAGMA journal_mode = WAL;")
        try db.execute("""
        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT NOT NULL PRIMARY KEY,
            startedAt INTEGER,
            method TEXT,
            url TEXT,
            host TEXT,
            path TEXT,
            scheme TEXT,
            requestHeaders TEXT,
            requestContentType TEXT,
            requestContentLength INTEGER,
            requestBody TEXT,
            requestBodyKind TEXT,
            completedAt INTEGER,
            tookMs INTEGER,
            statusCode INTEGER,
            statusMessage TEXT,
            protocolName TEXT,
            responseHeaders TEXT,
            responseContentType TEXT,
            responseContentLength INTEGER,
            responseBody TEXT,
            responseBodyKind TEXT,
            responseImageBytes BLOB,
            error TEXT
        );
        """)
        try db.execute(
            "CREATE INDEX IF NOT EXISTS idx_transactions_startedAt ON transactions(startedAt DESC);"
        )
    }

    // MARK: - Writes

    /// Insert or replace the full row (used for both the initial request row and
    /// read-modify-write merges).
    func upsert(_ tx: HttpTransaction) throws {
        let sql = """
        INSERT OR REPLACE INTO transactions (\(HttpTransactionDao.columns))
        VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24);
        """
        let stmt = try db.prepare(sql)
        stmt.bind(1, tx.id)
            .bind(2, tx.startedAt)
            .bind(3, tx.method)
            .bind(4, tx.url)
            .bind(5, tx.host)
            .bind(6, tx.path)
            .bind(7, tx.scheme)
            .bind(8, encodeHeaders(tx.requestHeaders))
            .bind(9, tx.requestContentType)
            .bind(10, tx.requestContentLength)
            .bind(11, tx.requestBody)
            .bind(12, tx.requestBodyKind)
            .bind(13, tx.completedAt)
            .bind(14, tx.tookMs)
            .bind(15, tx.statusCode.map(Int64.init))
            .bind(16, tx.statusMessage)
            .bind(17, tx.protocolName)
            .bind(18, encodeHeaders(tx.responseHeaders))
            .bind(19, tx.responseContentType)
            .bind(20, tx.responseContentLength)
            .bind(21, tx.responseBody)
            .bind(22, tx.responseBodyKind)
            .bind(23, tx.responseImageBytes)
            .bind(24, tx.error)
        _ = try stmt.step()
    }

    func clear() throws {
        try db.execute("DELETE FROM transactions;")
    }

    func deleteOlderThan(_ cutoffMs: Int64) throws {
        let stmt = try db.prepare(
            "DELETE FROM transactions WHERE COALESCE(startedAt, completedAt, 0) < ?1;"
        )
        stmt.bind(1, cutoffMs)
        _ = try stmt.step()
    }

    // MARK: - Reads

    func count() throws -> Int {
        let stmt = try db.prepare("SELECT COUNT(*) FROM transactions;")
        return try stmt.step() ? (stmt.int(0) ?? 0) : 0
    }

    func byId(_ id: String) throws -> HttpTransaction? {
        let stmt = try db.prepare(
            "SELECT \(HttpTransactionDao.columns) FROM transactions WHERE id = ?1;"
        )
        stmt.bind(1, id)
        return try stmt.step() ? map(stmt) : nil
    }

    func all() throws -> [HttpTransaction] {
        let stmt = try db.prepare(
            "SELECT \(HttpTransactionDao.columns) FROM transactions "
            + "ORDER BY COALESCE(startedAt, completedAt, 0) DESC;"
        )
        var rows: [HttpTransaction] = []
        while try stmt.step() { rows.append(map(stmt)) }
        return rows
    }

    /// Case-insensitive substring match over url / method / status / host.
    func filtered(_ query: String) throws -> [HttpTransaction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try all() }
        let like = "%\(trimmed)%"
        let stmt = try db.prepare("""
        SELECT \(HttpTransactionDao.columns) FROM transactions
        WHERE url LIKE ?1 COLLATE NOCASE
           OR method LIKE ?1 COLLATE NOCASE
           OR host LIKE ?1 COLLATE NOCASE
           OR CAST(statusCode AS TEXT) LIKE ?1
        ORDER BY COALESCE(startedAt, completedAt, 0) DESC;
        """)
        stmt.bind(1, like)
        var rows: [HttpTransaction] = []
        while try stmt.step() { rows.append(map(stmt)) }
        return rows
    }

    // MARK: - Row mapping

    private func map(_ s: SQLiteDatabase.Statement) -> HttpTransaction {
        HttpTransaction(
            id: s.string(0) ?? "",
            startedAt: s.int64(1) ?? 0,
            method: s.string(2) ?? "",
            url: s.string(3) ?? "",
            host: s.string(4) ?? "",
            path: s.string(5) ?? "",
            scheme: s.string(6) ?? "",
            requestHeaders: decodeHeaders(s.string(7)),
            requestContentType: s.string(8),
            requestContentLength: s.int64(9),
            requestBody: s.string(10),
            requestBodyKind: s.string(11) ?? BodyKinds.none,
            completedAt: s.int64(12),
            tookMs: s.int64(13),
            statusCode: s.int(14),
            statusMessage: s.string(15),
            protocolName: s.string(16),
            responseHeaders: decodeHeaders(s.string(17)),
            responseContentType: s.string(18),
            responseContentLength: s.int64(19),
            responseBody: s.string(20),
            responseBodyKind: s.string(21),
            responseImageBytes: s.data(22),
            error: s.string(23)
        )
    }

    // MARK: - Header (de)serialization

    private func encodeHeaders(_ headers: [String: String]) -> String {
        guard !headers.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: headers),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private func decodeHeaders(_ json: String?) -> [String: String] {
        guard let json = json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let map = obj as? [String: String] else { return [:] }
        return map
    }
}
#endif
