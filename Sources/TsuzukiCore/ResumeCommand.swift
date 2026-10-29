import Foundation

public enum ResumeCommand {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case invalidSessionID(String)
        case invalidPath(String)

        public var description: String {
            switch self {
            case .invalidSessionID(let id): return "The session ID “\(id)” has unexpected characters, so it was not run."
            case .invalidPath(let path): return "The project path “\(path)” contains control characters, so it was not run."
            }
        }
    }

    /// Shell command typed into the new iTerm tab, e.g.
    /// `cd '/Users/me/work/webapp' && claude --resume '0f1e…'`.
    public static func make(provider: Provider, sessionID: String, projectPath: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !sessionID.isEmpty, sessionID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw Failure.invalidSessionID(sessionID)
        }
        // A newline would submit the command early when typed into the terminal.
        guard !projectPath.isEmpty, !projectPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw Failure.invalidPath(projectPath)
        }

        let resume: String
        switch provider {
        case .claude: resume = "claude --resume"
        case .codex: resume = "codex resume"
        }
        return "cd \(shellQuote(projectPath)) && \(resume) \(shellQuote(sessionID))"
    }

    public static func make(for session: Session) throws -> String {
        try make(provider: session.provider, sessionID: session.sessionID, projectPath: session.projectPath)
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
