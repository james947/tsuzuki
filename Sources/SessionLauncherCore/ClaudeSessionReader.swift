import Foundation

/// Reads Claude Code transcripts from `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`.
///
/// Transcripts are append-only, so each file is scanned once and later refreshes only
/// read bytes appended since the previous scan. Files are opened read-only.
public final class ClaudeSessionReader: @unchecked Sendable {
    struct ScanState: Equatable {
        var firstCwd: String?
        var matchingCwd: String?
        var entrypoint: String?
        var firstPrompt: String?
        var aiTitle: String?
        var customTitle: String?
        var lastPrompt: String?
        var hasUserText = false
        var recognizedRecords = 0

        var needsUserRecords: Bool { matchingCwd == nil || firstPrompt == nil || entrypoint == nil }
    }

    private struct CacheEntry {
        var offset: UInt64
        var state: ScanState
    }

    private static let userMarkers = markers("user")
    private static let aiTitleMarkers = markers("ai-title")
    private static let customTitleMarkers = markers("custom-title")
    private static let lastPromptMarkers = markers("last-prompt")

    /// Claude writes compact JSON today; the spaced form is accepted in case that changes.
    private static func markers(_ type: String) -> [Data] {
        [Data(#""type":"\#(type)""#.utf8), Data(#""type": "\#(type)""#.utf8)]
    }

    private let claudeHome: URL
    private let isProcessAlive: (Int32) -> Bool
    private let scanner = LineScanner()
    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()

    public init(
        claudeHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
        isProcessAlive: @escaping (Int32) -> Bool = ProcessCheck.isAlive
    ) {
        self.claudeHome = claudeHome
        self.isProcessAlive = isProcessAlive
    }

    public func read() -> ProviderResult {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        let projects = claudeHome.appendingPathComponent("projects")
        guard let folders = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else {
            return .unavailable("No Claude sessions found in \(projects.path)")
        }

        let running = runningSessions()
        var sessions: [Session] = []
        var transcriptCount = 0
        var unrecognized = 0
        var seen = Set<String>()

        for folder in folders {
            // Subagent transcripts live one level deeper and are deliberately not listed.
            guard let files = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                seen.insert(file.path)
                guard let (state, bytesRead) = scan(file), bytesRead > 0 else { continue }
                transcriptCount += 1
                // A non-empty transcript with none of the expected records was probably
                // written in a newer format; report it rather than silently dropping it.
                if state.recognizedRecords == 0 { unrecognized += 1 }
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if let session = Self.makeSession(
                    sessionID: file.deletingPathExtension().lastPathComponent,
                    folderName: folder.lastPathComponent,
                    state: state,
                    lastActivity: modified,
                    running: running
                ) {
                    sessions.append(session)
                }
            }
        }
        cache = cache.filter { seen.contains($0.key) }

        if transcriptCount > 0 && unrecognized == transcriptCount {
            return .unsupported("Claude transcripts were found but none could be read. The transcript format may have changed.")
        }
        if unrecognized > 0 {
            return .partial(sessions, "\(unrecognized) of \(transcriptCount) transcripts couldn't be read and are not listed. The transcript format may have changed.")
        }
        return .sessions(sessions)
    }

    /// Re-checks Claude's process registry right before opening, since the list may have
    /// been loaded before another tab resumed the session.
    public func currentActivity(sessionID: String) -> ActivityHint? {
        runningSessions()[sessionID].map { .running(pid: $0) }
    }

    static func makeSession(
        sessionID: String,
        folderName: String,
        state: ScanState,
        lastActivity: Date,
        running: [String: Int32]
    ) -> Session? {
        // Print-mode and SDK runs are not interactive conversations.
        if let entrypoint = state.entrypoint, entrypoint.hasPrefix("sdk") { return nil }
        guard state.hasUserText, let cwd = state.matchingCwd ?? state.firstCwd else { return nil }

        let title = state.customTitle
            ?? state.aiTitle
            ?? state.firstPrompt.flatMap { TextExcerpt.make($0) }
            ?? TextExcerpt.fallbackTitle(projectPath: cwd, sessionID: sessionID)

        return Session(
            provider: .claude,
            sessionID: sessionID,
            title: title,
            projectPath: cwd,
            lastActivity: lastActivity,
            lastPrompt: state.lastPrompt.flatMap { TextExcerpt.isInjected($0) ? nil : TextExcerpt.make($0) },
            activity: running[sessionID].map { .running(pid: $0) }
        )
    }

    /// Claude names each project folder after the launch directory with every
    /// non-alphanumeric character replaced by `-`. The mapping is lossy, so it is only
    /// used to pick which recorded `cwd` the session was started from.
    static func encodedFolderName(for path: String) -> String {
        String(path.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
    }

    /// Returns the scan state and how many complete bytes of the file have been read.
    private func scan(_ file: URL) -> (ScanState, UInt64)? {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(UInt64.init) ?? 0
        var entry = cache[file.path] ?? CacheEntry(offset: 0, state: ScanState())
        if size < entry.offset {
            entry = CacheEntry(offset: 0, state: ScanState())
        }
        if size == entry.offset {
            return (entry.state, entry.offset)
        }

        let folderName = file.deletingLastPathComponent().lastPathComponent
        var state = entry.state
        do {
            entry.offset = try scanner.scan(url: file, from: entry.offset) { line in
                Self.apply(line: line, folderName: folderName, to: &state)
            }
        } catch {
            return cache[file.path].map { ($0.state, $0.offset) }
        }
        entry.state = state
        cache[file.path] = entry
        return (state, entry.offset)
    }

    /// Small lines are searched in full, so key order doesn't matter for the title and
    /// prompt records. In large lines (tool output, long pastes) only the head is searched:
    /// the top-level `"type"` is written near the start, while nested content deeper in
    /// those lines can contain the same text.
    static let fullSearchLimit = 64 << 10
    static let headSearchBytes = 4 << 10

    private static func hasMarker(_ line: Data, _ markers: [Data]) -> Bool {
        let region = line.count <= fullSearchLimit ? line : line.prefix(headSearchBytes)
        return markers.contains { region.range(of: $0) != nil }
    }

    static func apply(line: Data, folderName: String, to state: inout ScanState) {
        if hasMarker(line, userMarkers) {
            guard state.needsUserRecords else { return }
            guard let record = json(line), record["type"] as? String == "user" else { return }
            state.recognizedRecords += 1
            applyUser(record, folderName: folderName, to: &state)
        } else if hasMarker(line, aiTitleMarkers) {
            guard let record = recognized(line, type: "ai-title", in: &state) else { return }
            if let title = record["aiTitle"] as? String, !title.isEmpty { state.aiTitle = title }
        } else if hasMarker(line, customTitleMarkers) {
            guard let record = recognized(line, type: "custom-title", in: &state) else { return }
            if let title = record["customTitle"] as? String, !title.isEmpty { state.customTitle = title }
        } else if hasMarker(line, lastPromptMarkers) {
            guard let record = recognized(line, type: "last-prompt", in: &state) else { return }
            if let prompt = record["lastPrompt"] as? String, !prompt.isEmpty { state.lastPrompt = prompt }
        }
    }

    /// Parses a record of a known type. It counts as recognised even when the field this
    /// app wants is absent: sessions closed before any prompt write `last-prompt` records
    /// without a prompt, and that is not a format change.
    private static func recognized(_ line: Data, type: String, in state: inout ScanState) -> [String: Any]? {
        guard let record = json(line), record["type"] as? String == type else { return nil }
        state.recognizedRecords += 1
        return record
    }

    private static func applyUser(_ record: [String: Any], folderName: String, to state: inout ScanState) {
        if record["isSidechain"] as? Bool == true || record["isMeta"] as? Bool == true { return }

        if let cwd = record["cwd"] as? String, !cwd.isEmpty {
            if state.firstCwd == nil { state.firstCwd = cwd }
            if state.matchingCwd == nil, encodedFolderName(for: cwd) == folderName {
                state.matchingCwd = cwd
            }
        }
        if state.entrypoint == nil, let entrypoint = record["entrypoint"] as? String {
            state.entrypoint = entrypoint
        }
        guard let text = userText(record), !TextExcerpt.isInjected(text) else { return }
        state.hasUserText = true
        if state.firstPrompt == nil { state.firstPrompt = text }
    }

    private static func userText(_ record: [String: Any]) -> String? {
        guard let message = record["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String { return text }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        let texts = blocks.compactMap { block -> String? in
            block["type"] as? String == "text" ? block["text"] as? String : nil
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    /// Claude registers each running session in `~/.claude/sessions/<pid>.json`.
    /// Entries can outlive a crashed process, so the pid is checked too.
    func runningSessions() -> [String: Int32] {
        let folder = claudeHome.appendingPathComponent("sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [String: Int32] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = Self.json(data),
                  let sessionID = record["sessionId"] as? String,
                  let pid = (record["pid"] as? NSNumber)?.int32Value,
                  isProcessAlive(pid)
            else { continue }
            result[sessionID] = pid
        }
        return result
    }

    static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

public enum ProcessCheck {
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
