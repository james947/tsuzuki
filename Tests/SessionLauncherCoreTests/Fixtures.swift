import Foundation
import SQLite3
import XCTest

/// Builds small, hand-made provider data in a temporary folder.
final class FixtureDirectory {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-launcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    @discardableResult
    func writeLines(_ path: String, _ records: [Any]) throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = try records.map { record -> String in
            if let raw = record as? String { return raw }
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func append(_ path: String, _ text: String) throws {
        let handle = try FileHandle(forWritingTo: url(path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func sqlite(_ path: String, _ statements: [String]) throws {
        let url = url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw XCTSkip("Could not create SQLite fixture") }
        defer { sqlite3_close(db) }
        for statement in statements {
            var error: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, statement, nil, nil, &error) != SQLITE_OK {
                let message = error.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(error)
                XCTFail("SQLite fixture failed: \(message)\n\(statement)")
            }
        }
    }
}

enum ClaudeRecord {
    static func user(_ text: String, cwd: String, entrypoint: String = "cli", isMeta: Bool? = nil) -> [String: Any] {
        var record: [String: Any] = [
            "type": "user", "cwd": cwd, "entrypoint": entrypoint, "isSidechain": false,
            "sessionId": "s", "message": ["role": "user", "content": text],
        ]
        if let isMeta { record["isMeta"] = isMeta }
        return record
    }

    static func toolResult(cwd: String) -> [String: Any] {
        [
            "type": "user", "cwd": cwd, "entrypoint": "cli", "isSidechain": false, "sessionId": "s",
            "message": ["role": "user", "content": [["type": "tool_result", "content": "ok"]]],
        ]
    }

    static func aiTitle(_ title: String) -> [String: Any] {
        ["type": "ai-title", "aiTitle": title, "sessionId": "s"]
    }

    static func customTitle(_ title: String) -> [String: Any] {
        ["type": "custom-title", "customTitle": title, "sessionId": "s"]
    }

    static func lastPrompt(_ prompt: String) -> [String: Any] {
        ["type": "last-prompt", "lastPrompt": prompt, "sessionId": "s"]
    }
}

enum CodexFixture {
    static let createThreads = """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY, rollout_path TEXT, cwd TEXT, title TEXT, name TEXT,
            first_user_message TEXT, updated_at INTEGER, archived INTEGER, source TEXT, is_pinned INTEGER
        )
        """

    static func insert(
        id: String, cwd: String = "/work/app", title: String = "", name: String? = nil,
        firstMessage: String = "hello", updatedAt: Int = 1_000, archived: Int = 0,
        source: String = "cli", pinned: Int = 0, rollout: String = ""
    ) -> String {
        func quote(_ value: String?) -> String {
            guard let value else { return "NULL" }
            return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
        }
        return """
            INSERT INTO threads VALUES (\(quote(id)), \(quote(rollout)), \(quote(cwd)), \(quote(title)),
            \(quote(name)), \(quote(firstMessage)), \(updatedAt), \(archived), \(quote(source)), \(pinned))
            """
    }

    static func userMessage(_ texts: [String]) -> [String: Any] {
        [
            "type": "response_item",
            "payload": [
                "type": "message", "role": "user",
                "content": texts.map { ["type": "input_text", "text": $0] },
            ],
        ]
    }
}
