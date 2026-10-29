import AppKit
import TsuzukiCore

@MainActor
final class LauncherModel: ObservableObject {
    struct ActiveWarning: Identifiable {
        let session: Session
        let activity: ActivityHint
        var id: String { session.id }

        var message: String {
            switch activity {
            case .running(let pid):
                return "Claude reports this conversation is running (process \(pid)). Opening it again means two tabs write to the same conversation."
            case .recentlyActive(let seconds):
                return "This conversation was updated \(seconds) seconds ago and may still be open in another tab."
            }
        }
    }

    /// Filtered lists are computed once per change rather than on every view update.
    @Published private(set) var pinned: [Session] = []
    @Published private(set) var recent: [Session] = []
    @Published private(set) var providerMessages: [Provider: String] = [:]
    @Published private(set) var marks: [String: SessionMark] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var archivedCount = 0
    @Published var query = "" {
        didSet { if query != oldValue { recompute(selectFirst: true) } }
    }
    @Published var showArchived = false {
        didSet { if showArchived != oldValue { recompute(selectFirst: false) } }
    }
    @Published var selectedID: String?
    @Published var errorMessage: String?
    @Published var activeWarning: ActiveWarning?

    /// Pinned first, then most recent; this is also the keyboard navigation order.
    private(set) var ordered: [Session] = []

    private var sessions: [Session] = []
    private var haystacks: [String: String] = [:]

    private let claudeReader = ClaudeSessionReader()
    private let codexReader = CodexSessionReader()
    private let marksStore = SessionMarksStore()
    private var promptTask: Task<Void, Never>?

    init() {
        do {
            marks = try marksStore.load()
        } catch {
            errorMessage = "Couldn't read saved pins and notes: \(error.localizedDescription)"
        }
        // Warm the transcript caches at launch so the first click on the menu-bar icon is fast.
        refresh()
    }

    func isPinned(_ session: Session) -> Bool {
        marks[session.id]?.pinned ?? session.providerPinned
    }

    func note(for session: Session) -> String {
        marks[session.id]?.note ?? ""
    }

    // MARK: - Filtering

    private func setSessions(_ newSessions: [Session]) {
        sessions = newSessions
        haystacks = Dictionary(
            newSessions.map { ($0.id, SessionSearch.haystack(for: $0, note: note(for: $0))) },
            uniquingKeysWith: { first, _ in first }
        )
        archivedCount = newSessions.filter(\.isArchived).count
        recompute(selectFirst: false)
    }

    private func recompute(selectFirst: Bool) {
        let words = SessionSearch.words(in: query)
        var newPinned: [Session] = []
        var newRecent: [Session] = []
        for session in sessions where showArchived || !session.isArchived {
            if !words.isEmpty, !SessionSearch.matches(haystack: haystacks[session.id] ?? "", words: words) {
                continue
            }
            if isPinned(session) { newPinned.append(session) } else { newRecent.append(session) }
        }
        pinned = newPinned
        recent = newRecent
        ordered = newPinned + newRecent

        if selectFirst || !ordered.contains(where: { $0.id == selectedID }) {
            selectedID = ordered.first?.id
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let claudeReader = claudeReader
        let codexReader = codexReader

        Task {
            async let claude = Task.detached(priority: .userInitiated) { claudeReader.read() }.value
            async let codex = Task.detached(priority: .userInitiated) { codexReader.read() }.value
            let results: [(Provider, ProviderResult)] = [(.claude, await claude), (.codex, await codex)]

            var messages: [Provider: String] = [:]
            var merged: [Session] = []
            for (provider, result) in results {
                switch result {
                case .sessions(let list): merged += list
                case .partial(let list, let message):
                    merged += list
                    messages[provider] = message
                case .unavailable(let message): messages[provider] = message
                case .unsupported(let message): messages[provider] = "Unsupported: \(message)"
                }
            }
            let previousPrompts = Dictionary(
                sessions.compactMap { s in s.lastPrompt.map { (s.id, $0) } }, uniquingKeysWith: { a, _ in a }
            )
            for index in merged.indices where merged[index].provider == .codex {
                merged[index].lastPrompt = previousPrompts[merged[index].id]
            }
            merged.sort { $0.lastActivity > $1.lastActivity }

            // Skip redrawing when nothing changed since the window was last opened.
            if merged != sessions { setSessions(merged) }
            if messages != providerMessages { providerMessages = messages }
            isLoading = false
            loadCodexPrompts()
        }
    }

    /// Codex last prompts come from large rollout files, so they load after the list is
    /// shown, visible order first. Updates are applied per batch to keep redraws rare.
    private func loadCodexPrompts() {
        promptTask?.cancel()
        var seen = Set<String>()
        let paths = (ordered + sessions)
            .filter { $0.provider == .codex && seen.insert($0.id).inserted }
            .compactMap { session in session.transcriptPath.map { (session.id, $0) } }
        let reader = codexReader

        promptTask = Task { [weak self] in
            for start in stride(from: 0, to: paths.count, by: 100) {
                if Task.isCancelled { return }
                let batch = Array(paths[start..<min(start + 100, paths.count)])
                let found = await Task.detached(priority: .utility) {
                    batch.map { ($0.0, reader.lastPrompt(transcriptPath: $0.1)) }
                }.value
                guard let self, !Task.isCancelled else { return }

                let positions = Dictionary(
                    self.sessions.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }
                )
                var updated = self.sessions
                for (id, prompt) in found {
                    if let index = positions[id], updated[index].lastPrompt != prompt {
                        updated[index].lastPrompt = prompt
                    }
                }
                if updated != self.sessions { self.setSessions(updated) }
            }
        }
    }

    // MARK: - Pins and notes

    func togglePin(_ session: Session) {
        var mark = marks[session.id] ?? SessionMark()
        let pinned = !isPinned(session)
        // Store an override only when it differs from the provider's own pin.
        mark.pinned = pinned == session.providerPinned ? nil : pinned
        updateMark(mark, for: session)
    }

    func setNote(_ note: String, for session: Session) {
        var mark = marks[session.id] ?? SessionMark()
        mark.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updateMark(mark, for: session)
    }

    private func updateMark(_ mark: SessionMark, for session: Session) {
        marks[session.id] = mark
        haystacks[session.id] = SessionSearch.haystack(for: session, note: mark.note)
        recompute(selectFirst: false)
        do {
            try marksStore.save(marks)
        } catch {
            errorMessage = "Couldn't save pins and notes: \(error.localizedDescription)"
        }
    }

    // MARK: - Selection and opening

    func moveSelection(by offset: Int) {
        guard !ordered.isEmpty else { return }
        let current = ordered.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + offset, 0), ordered.count - 1)
        selectedID = ordered[next].id
    }

    func openSelected() {
        guard let session = ordered.first(where: { $0.id == selectedID }) ?? ordered.first else { return }
        open(session)
    }

    func open(_ session: Session, confirmed: Bool = false) {
        selectedID = session.id
        // Checked now rather than at the last refresh: another tab may have resumed the
        // session while this window was open.
        if !confirmed, let activity = currentActivity(of: session) {
            activeWarning = ActiveWarning(session: session, activity: activity)
            return
        }
        do {
            try ITermLauncher.open(session)
            errorMessage = nil
        } catch let failure as ITermLauncher.Failure {
            errorMessage = failure.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func currentActivity(of session: Session) -> ActivityHint? {
        switch session.provider {
        case .claude: return claudeReader.currentActivity(sessionID: session.sessionID)
        case .codex: return codexReader.currentActivity(sessionID: session.sessionID)
        }
    }

    func copyCommand(_ session: Session) {
        do {
            let command = try ResumeCommand.make(for: session)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func revealProject(_ session: Session) {
        guard FileManager.default.fileExists(atPath: session.projectPath) else {
            errorMessage = "The project folder no longer exists:\n\(session.projectPath)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.projectPath)])
    }
}
