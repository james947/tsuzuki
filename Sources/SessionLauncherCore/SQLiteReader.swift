import Foundation
import SQLite3

/// Minimal read-only SQLite access. The database is opened with `SQLITE_OPEN_READONLY`
/// (not `immutable`) so reads see Codex's latest committed WAL data without writing.
final class SQLiteReader {
    enum Value {
        case text(String)
        case integer(Int64)
        case null

        var string: String? {
            switch self {
            case .text(let value): return value
            case .integer(let value): return String(value)
            case .null: return nil
            }
        }

        var int: Int64? {
            switch self {
            case .integer(let value): return value
            case .text(let value): return Int64(value)
            case .null: return nil
            }
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private var db: OpaquePointer?

    init(path: String) throws {
        let status = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "status \(status)"
            sqlite3_close(db)
            db = nil
            throw Failure(description: message)
        }
        sqlite3_busy_timeout(db, 1000)
    }

    deinit {
        sqlite3_close(db)
    }

    func query(_ sql: String) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure(description: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var rows: [[Value]] = []
        let columns = sqlite3_column_count(statement)
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw Failure(description: String(cString: sqlite3_errmsg(db)))
            }
            rows.append((0..<columns).map { index in
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    return .integer(sqlite3_column_int64(statement, index))
                case SQLITE_NULL:
                    return .null
                default:
                    guard let text = sqlite3_column_text(statement, index) else { return .null }
                    return .text(String(cString: text))
                }
            })
        }
        return rows
    }
}
