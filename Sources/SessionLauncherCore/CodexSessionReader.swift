import Foundation

/// Reads Codex sessions from the `threads` table in `~/.codex/state_<N>.sqlite`, and the
/// last prompt from the end of each session's rollout file. Nothing is written.
public final class CodexSessionReader: @unchecked Sendable {
    static let requiredColumns: Set<String> = [
        "id", "rollout_path", "cwd", "title", "name", "first_user_message",
        "updated_at", "archived", "source",
    ]
    /// Top-level interactive sessions. Subagent sources are JSON objects; `exec` is
    /// non-interactive. Recent TUI sessions are recorded as `vscode`.
    static let interactiveSources = ["cli", "vscode"]

    private static let userRoleMarker = Data(#""role":"user""#.utf8)
    private static let tailWindows = [256 << 10, 2 << 20, 8 << 20]

    private let codexHome: URL
    private let now: () -> Date
    private let recentWindow: TimeInterval
    private var promptCache: [String: (size: UInt64, prompt: String?)] = [:]
    private let lock = NSLock()

    public init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        recentWindow: TimeInterval = 120,
        now: @escaping () -> Date = Date.init
    ) {
        self.codexHome = codexHome
        self.recentWindow = recentWindow
        self.now = now
    }

    public func read() -> ProviderResult {
        guard FileManager.default.fileExists(atPath: codexHome.path) else {
            return .unavailable("No Codex data found in \(codexHome.path)")
        }
        guard let database = latestStateDatabase() else {
            return .unsupported("Codex data exists but no state_<N>.sqlite database was found. The storage format may have changed.")
        }

        let reader: SQLiteReader
        let columns: Set<String>
        do {
            reader = try SQLiteReader(path: database.path)
            columns = Set(try reader.query("PRAGMA table_info(threads)").compactMap { $0[1].string })
        } catch {
            return .unsupported("Could not read \(database.lastPathComponent): \(error)")
        }
        let missing = Self.requiredColumns.subtracting(columns)
        guard missing.isEmpty else {
            let names = missing.sorted().joined(separator: ", ")
            return .unsupported("\(database.lastPathComponent) is missing expected columns (\(names)). The Codex format may have changed.")
        }

        let pinnedColumn = columns.contains("is_pinned") ? "is_pinned" : "0"
        let sources = Self.interactiveSources.map { "'\($0)'" }.joined(separator: ",")
        let sql = """
            SELECT id, cwd, coalesce(name, ''), coalesce(title, ''), coalesce(first_user_message, ''),
                   updated_at, archived, \(pinnedColumn), rollout_path
            FROM threads
            WHERE source IN (\(sources))
              AND (coalesce(first_user_message, '') != '' OR coalesce(name, '') != '')
            ORDER BY updated_at DESC
            """

        let rows: [[SQLiteReader.Value]]
        do {
            rows = try reader.query(sql)
        } catch {
            return .unsupported("Could not query Codex sessions: \(error)")
        }
        let currentTime = now()
        return .sessions(rows.compactMap { Self.makeSession(row: $0, now: currentTime, recentWindow: recentWindow) })
    }

    static func makeSession(row: [SQLiteReader.Value], now: Date, recentWindow: TimeInterval) -> Session? {
        guard let id = row[0].string, !id.isEmpty, let cwd = row[1].string, !cwd.isEmpty else { return nil }
        let name = row[2].string ?? ""
        let title = row[3].string ?? ""
        let firstMessage = row[4].string ?? ""
        let updated = Date(timeIntervalSince1970: TimeInterval(row[5].int ?? 0))

        let displayTitle = [name, title].first { !$0.isEmpty }.flatMap { TextExcerpt.make($0) }
            ?? TextExcerpt.make(firstMessage)
            ?? TextExcerpt.fallbackTitle(projectPath: cwd, sessionID: id)

        // Codex has no registry of running sessions, so recent writes are the best signal.
        let secondsAgo = Int(now.timeIntervalSince(updated))
        let activity: ActivityHint? = (0..<Int(recentWindow)).contains(secondsAgo)
            ? .recentlyActive(secondsAgo: secondsAgo) : nil

        return Session(
            provider: .codex,
            sessionID: id,
            title: displayTitle,
            projectPath: cwd,
            lastActivity: updated,
            isArchived: (row[6].int ?? 0) != 0,
            providerPinned: (row[7].int ?? 0) != 0,
            activity: activity,
            transcriptPath: row[8].string
        )
    }

    /// Re-reads one session's last update right before opening, since the list may have
    /// been loaded before another tab resumed it.
    public func currentActivity(sessionID: String) -> ActivityHint? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard sessionID.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              let database = latestStateDatabase(),
              let reader = try? SQLiteReader(path: database.path),
              let row = try? reader.query("SELECT updated_at FROM threads WHERE id = '\(sessionID)'").first,
              let updated = row.first?.int
        else { return nil }
        let secondsAgo = Int(now().timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(updated))))
        return (0..<Int(recentWindow)).contains(secondsAgo) ? .recentlyActive(secondsAgo: secondsAgo) : nil
    }

    func latestStateDatabase() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: codexHome.path)) ?? []
        let versioned = files.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite") else { return nil }
            let number = name.dropFirst("state_".count).dropLast(".sqlite".count)
            return Int(number).map { ($0, name) }
        }
        return versioned.max { $0.0 < $1.0 }.map { codexHome.appendingPathComponent($0.1) }
    }

    /// The last prompt the user typed, read from the end of the rollout file. Rollouts can
    /// be hundreds of megabytes, so only growing tail windows are read, and results are
    /// cached until the file changes size.
    public func lastPrompt(transcriptPath: String) -> String? {
        let url = URL(fileURLWithPath: transcriptPath)
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(UInt64.init) else {
            return nil
        }
        lock.lock()
        if let cached = promptCache[transcriptPath], cached.size == size {
            lock.unlock()
            return cached.prompt
        }
        lock.unlock()

        let prompt = autoreleasepool { Self.findLastPrompt(in: url, size: size) }
        lock.lock()
        promptCache[transcriptPath] = (size, prompt)
        lock.unlock()
        return prompt
    }

    static func findLastPrompt(in url: URL, size: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        for window in tailWindows {
            let start = size > UInt64(window) ? size - UInt64(window) : 0
            guard (try? handle.seek(toOffset: start)) != nil,
                  let data = try? handle.read(upToCount: Int(size - start))
            else { return nil }

            var lines = data.split(separator: LineScanner.newline, omittingEmptySubsequences: true)
            if start > 0, !lines.isEmpty { lines.removeFirst() }  // likely a partial line
            for line in lines.reversed() where line.range(of: userRoleMarker) != nil {
                if let prompt = userPrompt(in: Data(line)) { return prompt }
            }
            if start == 0 { break }
        }
        return nil
    }

    static func userPrompt(in line: Data) -> String? {
        guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              record["type"] as? String == "response_item",
              let payload = record["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              payload["role"] as? String == "user",
              let content = payload["content"] as? [[String: Any]]
        else { return nil }

        let typed = content.compactMap { block -> String? in
            guard block["type"] as? String == "input_text", let text = block["text"] as? String,
                  !TextExcerpt.isInjected(text) else { return nil }
            return text
        }
        return typed.last.flatMap { TextExcerpt.make($0) }
    }
}
