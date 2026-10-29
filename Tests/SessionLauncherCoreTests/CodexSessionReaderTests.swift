import XCTest
@testable import SessionLauncherCore

final class CodexSessionReaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func reader(_ fixture: FixtureDirectory) -> CodexSessionReader {
        CodexSessionReader(codexHome: fixture.root, recentWindow: 120, now: { self.now })
    }

    func testFiltersToInteractiveSessionsAndPicksTitles() throws {
        let fixture = try FixtureDirectory()
        try fixture.sqlite("state_5.sqlite", [
            CodexFixture.createThreads,
            CodexFixture.insert(id: "named", title: "auto title", name: "Budget tool charts", updatedAt: 5_000),
            CodexFixture.insert(id: "titled", title: "Investigate flaky test", updatedAt: 4_000, source: "vscode"),
            CodexFixture.insert(id: "first-msg", title: "", firstMessage: "why is\nthis slow", updatedAt: 3_000),
            CodexFixture.insert(id: "subagent", source: #"{"subagent":{"other":"guardian"}}"#),
            CodexFixture.insert(id: "exec", source: "exec"),
            CodexFixture.insert(id: "empty", firstMessage: ""),
        ])

        let sessions = reader(fixture).read().sessions

        XCTAssertEqual(sessions.map(\.sessionID), ["named", "titled", "first-msg"])
        XCTAssertEqual(sessions.map(\.title), ["Budget tool charts", "Investigate flaky test", "why is"])
        XCTAssertEqual(sessions.first?.projectPath, "/work/app")
    }

    func testUsesHighestStateVersionAndReadsFlags() throws {
        let fixture = try FixtureDirectory()
        try fixture.sqlite("state_4.sqlite", [CodexFixture.createThreads, CodexFixture.insert(id: "old")])
        try fixture.sqlite("state_5.sqlite", [
            CodexFixture.createThreads,
            CodexFixture.insert(id: "archived", archived: 1, pinned: 1),
        ])

        let session = try XCTUnwrap(reader(fixture).read().sessions.first)

        XCTAssertEqual(session.sessionID, "archived")
        XCTAssertTrue(session.isArchived)
        XCTAssertTrue(session.providerPinned)
    }

    func testRecentActivityHint() throws {
        let fixture = try FixtureDirectory()
        try fixture.sqlite("state_5.sqlite", [
            CodexFixture.createThreads,
            CodexFixture.insert(id: "recent", updatedAt: 9_970),
            CodexFixture.insert(id: "old", updatedAt: 9_000),
        ])

        let activity = Dictionary(uniqueKeysWithValues: reader(fixture).read().sessions.map { ($0.sessionID, $0.activity) })

        XCTAssertEqual(activity["recent"], .some(.recentlyActive(secondsAgo: 30)))
        XCTAssertEqual(activity["old"], .some(nil))
    }

    func testCurrentActivityRereadsDatabase() throws {
        let fixture = try FixtureDirectory()
        try fixture.sqlite("state_5.sqlite", [
            CodexFixture.createThreads,
            CodexFixture.insert(id: "thread-1", updatedAt: 9_000),
        ])
        let reader = reader(fixture)
        XCTAssertNil(reader.currentActivity(sessionID: "thread-1"))

        try fixture.sqlite("state_5.sqlite", ["UPDATE threads SET updated_at = 9990 WHERE id = 'thread-1'"])

        XCTAssertEqual(reader.currentActivity(sessionID: "thread-1"), .recentlyActive(secondsAgo: 10))
        XCTAssertNil(reader.currentActivity(sessionID: "x' OR '1'='1"))
    }

    func testUnsupportedWhenColumnsChange() throws {
        let fixture = try FixtureDirectory()
        try fixture.sqlite("state_6.sqlite", ["CREATE TABLE threads (id TEXT, cwd TEXT)"])

        guard case .unsupported(let message) = reader(fixture).read() else {
            return XCTFail("Missing columns should be unsupported")
        }
        XCTAssertTrue(message.contains("rollout_path"))
    }

    func testUnavailableAndMissingDatabase() throws {
        let missing = CodexSessionReader(codexHome: URL(fileURLWithPath: "/nonexistent/.codex"))
        guard case .unavailable = missing.read() else { return XCTFail("Missing folder should be unavailable") }

        let noDatabase = try FixtureDirectory()
        guard case .unsupported = reader(noDatabase).read() else { return XCTFail("No database should be unsupported") }
    }

    func testLastPromptSkipsInjectedContextAndAssistantMessages() throws {
        let fixture = try FixtureDirectory()
        let rollout = try fixture.writeLines("sessions/rollout.jsonl", [
            CodexFixture.userMessage(["<environment_context>cwd</environment_context>"]),
            CodexFixture.userMessage(["compare the new chart colours"]),
            ["type": "response_item", "payload": ["type": "message", "role": "assistant",
                                                 "content": [["type": "output_text", "text": "done"]]]],
            CodexFixture.userMessage(["# AGENTS.md instructions for /work/app"]),
            ["type": "compacted", "payload": ["replacement_history": [["role": "user", "content": "old"]]]],
        ])

        XCTAssertEqual(reader(fixture).lastPrompt(transcriptPath: rollout.path), "compare the new chart colours")
    }

    func testLastPromptBeyondFirstTailWindow() throws {
        let fixture = try FixtureDirectory()
        let filler = (0..<40).map { _ in ["type": "event_msg", "payload": ["text": String(repeating: "y", count: 10_000)]] }
        let rollout = try fixture.writeLines("sessions/long.jsonl", [CodexFixture.userMessage(["the early prompt"])] + filler)

        XCTAssertEqual(reader(fixture).lastPrompt(transcriptPath: rollout.path), "the early prompt")
    }
}
