#if DEBUG
import Foundation
import SQLite3

/// A thin wrapper over the system `libsqlite3` — no third-party dependency, so
/// nothing extra can leak into a release build (the whole file is `#if DEBUG`).
/// Just enough surface for the DAO: open, `execute`, `prepare`, and a small
/// prepared-`Statement` with tolerant binders/column getters.
final class SQLiteDatabase {
    /// SQLite wants a copy of bound text/blobs (they may be freed before step).
    private static let transient = unsafeBitCast(
        -1, to: sqlite3_destructor_type.self
    )

    private let handle: OpaquePointer

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db = db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db = db { sqlite3_close(db) }
            throw SQLiteError.open(message)
        }
        self.handle = db
    }

    deinit { sqlite3_close(handle) }

    /// Runs a statement with no result rows (DDL, INSERT, DELETE, PRAGMA).
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw SQLiteError.exec(message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt = stmt else {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        return Statement(stmt: stmt, transient: SQLiteDatabase.transient)
    }

    enum SQLiteError: Error {
        case open(String)
        case exec(String)
        case prepare(String)
        case step(String)
    }

    /// A prepared statement. 1-based bind indices, 0-based column indices —
    /// matching the SQLite C API.
    final class Statement {
        private let stmt: OpaquePointer
        private let transient: sqlite3_destructor_type

        init(stmt: OpaquePointer, transient: sqlite3_destructor_type) {
            self.stmt = stmt
            self.transient = transient
        }

        deinit { sqlite3_finalize(stmt) }

        // MARK: Binding

        @discardableResult func bind(_ index: Int32, _ value: String?) -> Statement {
            if let value = value {
                sqlite3_bind_text(stmt, index, value, -1, transient)
            } else {
                sqlite3_bind_null(stmt, index)
            }
            return self
        }

        @discardableResult func bind(_ index: Int32, _ value: Int64?) -> Statement {
            if let value = value {
                sqlite3_bind_int64(stmt, index, value)
            } else {
                sqlite3_bind_null(stmt, index)
            }
            return self
        }

        @discardableResult func bind(_ index: Int32, _ value: Data?) -> Statement {
            if let value = value, !value.isEmpty {
                value.withUnsafeBytes { raw in
                    sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(value.count), transient)
                }
            } else if value != nil {
                // Empty (non-nil) blob.
                sqlite3_bind_blob(stmt, index, nil, 0, transient)
            } else {
                sqlite3_bind_null(stmt, index)
            }
            return self
        }

        // MARK: Stepping

        /// Advances to the next row. Returns true if a row is available.
        func step() throws -> Bool {
            let rc = sqlite3_step(stmt)
            switch rc {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            default: throw SQLiteError.step("step rc=\(rc)")
            }
        }

        // MARK: Column getters (0-based)

        func string(_ column: Int32) -> String? {
            guard sqlite3_column_type(stmt, column) != SQLITE_NULL,
                  let cString = sqlite3_column_text(stmt, column) else { return nil }
            return String(cString: cString)
        }

        func int64(_ column: Int32) -> Int64? {
            guard sqlite3_column_type(stmt, column) != SQLITE_NULL else { return nil }
            return sqlite3_column_int64(stmt, column)
        }

        func int(_ column: Int32) -> Int? {
            guard let v = int64(column) else { return nil }
            return Int(truncatingIfNeeded: v)
        }

        func data(_ column: Int32) -> Data? {
            guard sqlite3_column_type(stmt, column) != SQLITE_NULL else { return nil }
            let count = Int(sqlite3_column_bytes(stmt, column))
            guard count > 0, let bytes = sqlite3_column_blob(stmt, column) else { return nil }
            return Data(bytes: bytes, count: count)
        }
    }
}
#endif
