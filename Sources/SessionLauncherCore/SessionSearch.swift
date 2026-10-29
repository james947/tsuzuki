import Foundation

public enum SessionSearch {
    /// Every word in `query` must appear in the title, project, note, last prompt or provider.
    public static func matches(_ session: Session, note: String, query: String) -> Bool {
        matches(haystack: haystack(for: session, note: note), words: words(in: query))
    }

    public static func words(in query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Lowercased text searched for a session. Build it once per change, not per keystroke.
    public static func haystack(for session: Session, note: String) -> String {
        [session.title, session.projectPath, note, session.lastPrompt ?? "", session.provider.displayName]
            .joined(separator: "\n")
            .lowercased()
    }

    public static func matches(haystack: String, words: [String]) -> Bool {
        words.allSatisfy { haystack.contains($0) }
    }
}
