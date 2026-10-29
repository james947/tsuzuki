import Foundation

enum TextExcerpt {
    /// First non-empty line, whitespace collapsed, truncated for a one-line label.
    static func make(_ text: String, limit: Int = 90) -> String? {
        let line = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }

    /// Text injected by the tools (command wrappers, environment context, instructions)
    /// rather than typed by the user.
    static func isInjected(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed.hasPrefix("<")
            || trimmed.hasPrefix("# AGENTS.md")
            || trimmed.hasPrefix("Caveat: The messages below were generated")
    }

    static func fallbackTitle(projectPath: String, sessionID: String) -> String {
        let name = (projectPath as NSString).lastPathComponent
        let shortID = String(sessionID.prefix(8))
        if name.isEmpty && shortID.isEmpty { return "Untitled session" }
        if name.isEmpty { return "Session \(shortID)" }
        return "\(name) · \(shortID)"
    }
}
