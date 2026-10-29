import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

/// Why a session might already be open in another tab.
public enum ActivityHint: Equatable, Sendable {
    /// Claude's own registry lists a live process for this session.
    case running(pid: Int32)
    /// No process registry is available; the session was written to very recently.
    case recentlyActive(secondsAgo: Int)
}

public struct Session: Identifiable, Equatable, Sendable {
    public let provider: Provider
    public let sessionID: String
    public let title: String
    public let projectPath: String
    public let lastActivity: Date
    public var lastPrompt: String?
    public let isArchived: Bool
    public let providerPinned: Bool
    public let activity: ActivityHint?
    /// Codex only: the rollout file the last prompt is read from.
    public let transcriptPath: String?

    public var id: String { "\(provider.rawValue):\(sessionID)" }

    public var projectName: String {
        let name = (projectPath as NSString).lastPathComponent
        return name.isEmpty ? projectPath : name
    }

    public init(
        provider: Provider,
        sessionID: String,
        title: String,
        projectPath: String,
        lastActivity: Date,
        lastPrompt: String? = nil,
        isArchived: Bool = false,
        providerPinned: Bool = false,
        activity: ActivityHint? = nil,
        transcriptPath: String? = nil
    ) {
        self.provider = provider
        self.sessionID = sessionID
        self.title = title
        self.projectPath = projectPath
        self.lastActivity = lastActivity
        self.lastPrompt = lastPrompt
        self.isArchived = isArchived
        self.providerPinned = providerPinned
        self.activity = activity
        self.transcriptPath = transcriptPath
    }
}

/// Outcome of reading one provider, so one broken provider never hides the other.
public enum ProviderResult: Sendable {
    case sessions([Session])
    /// Some sessions were read, but some files were not recognised and are missing.
    case partial([Session], String)
    /// The provider is not installed or has no local data.
    case unavailable(String)
    /// Data exists but is in a format this app does not recognise.
    case unsupported(String)

    public var sessions: [Session] {
        switch self {
        case .sessions(let list), .partial(let list, _): return list
        case .unavailable, .unsupported: return []
        }
    }
}
