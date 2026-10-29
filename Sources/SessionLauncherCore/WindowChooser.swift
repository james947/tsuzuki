import Foundation

/// Picks the iTerm window whose open tabs are closest to a project folder, so a
/// conversation opens next to related work (e.g. `~/work/projects/*` tabs together).
public enum WindowChooser {
    public struct WindowTabs: Equatable {
        public let id: Int
        public var paths: [String]

        public init(id: Int, paths: [String]) {
            self.id = id
            self.paths = paths
        }
    }

    /// Parses `ITermScript.listTabPaths` output: one `windowID<TAB>path` line per tab,
    /// frontmost window first.
    public static func parse(_ output: String) -> [WindowTabs] {
        var windows: [WindowTabs] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let id = Int(parts[0]), !parts[1].isEmpty else { continue }
            if let index = windows.firstIndex(where: { $0.id == id }) {
                windows[index].paths.append(String(parts[1]))
            } else {
                windows.append(WindowTabs(id: id, paths: [String(parts[1])]))
            }
        }
        return windows
    }

    /// The window sharing the most leading path components with `projectPath`, or nil
    /// when no single window is the clear best match (the caller then uses the frontmost).
    public static func bestWindow(for projectPath: String, among windows: [WindowTabs]) -> Int? {
        let target = components(projectPath)
        let scored = windows.map { window in
            (id: window.id, score: window.paths.map { sharedPrefixLength(target, components($0)) }.max() ?? 0)
        }
        guard let best = scored.max(by: { $0.score < $1.score }), best.score > 0,
              scored.filter({ $0.score == best.score }).count == 1
        else { return nil }
        return best.id
    }

    private static func components(_ path: String) -> [Substring] {
        (path as NSString).standardizingPath.split(separator: "/")
    }

    private static func sharedPrefixLength(_ a: [Substring], _ b: [Substring]) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }
}
