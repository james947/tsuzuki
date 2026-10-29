import Foundation

/// The app's own pins and next-step notes, keyed by `Session.id`. Stored in
/// `~/Library/Application Support/SessionLauncher/marks.json`, never in provider files.
public struct SessionMark: Codable, Equatable, Sendable {
    /// nil follows the provider's own pin (Codex); an explicit value overrides it, so
    /// unpinning a Codex-pinned session is remembered.
    public var pinned: Bool?
    public var note: String

    public init(pinned: Bool? = nil, note: String = "") {
        self.pinned = pinned
        self.note = note
    }

    var isEmpty: Bool { pinned == nil && note.isEmpty }
}

public final class SessionMarksStore {
    private let fileURL: URL

    public init(fileURL: URL = SessionMarksStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SessionLauncher/marks.json")
    }

    public func load() throws -> [String: SessionMark] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        return try JSONDecoder().decode([String: SessionMark].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ marks: [String: SessionMark]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(marks.filter { !$0.value.isEmpty }).write(to: fileURL, options: .atomic)
    }
}
