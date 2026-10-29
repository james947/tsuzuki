import XCTest
@testable import TsuzukiCore

final class ResumeCommandTests: XCTestCase {
    func testProviderCommands() throws {
        XCTAssertEqual(
            try ResumeCommand.make(provider: .claude, sessionID: "abc-123", projectPath: "/work/app"),
            "cd '/work/app' && claude --resume 'abc-123'"
        )
        XCTAssertEqual(
            try ResumeCommand.make(provider: .codex, sessionID: "01a1-xyz", projectPath: "/work/app"),
            "cd '/work/app' && codex resume '01a1-xyz'"
        )
    }

    func testQuotesPathsWithSpacesAndQuotes() throws {
        let command = try ResumeCommand.make(provider: .claude, sessionID: "id", projectPath: #"/Users/me/Sam's "work" $HOME"#)
        XCTAssertEqual(command, #"cd '/Users/me/Sam'\''s "work" $HOME' && claude --resume 'id'"#)
    }

    func testRejectsUnsafeInput() {
        XCTAssertThrowsError(try ResumeCommand.make(provider: .claude, sessionID: "id; rm -rf ~", projectPath: "/work"))
        XCTAssertThrowsError(try ResumeCommand.make(provider: .codex, sessionID: "id", projectPath: "/work\nrm -rf ~"))
        XCTAssertThrowsError(try ResumeCommand.make(provider: .codex, sessionID: "", projectPath: "/work"))
    }

    func testAppleScriptEscapesCommand() throws {
        let command = try ResumeCommand.make(provider: .claude, sessionID: "id", projectPath: #"/a "b"\c"#)
        let script = ITermScript.openTab(running: command)

        XCTAssertTrue(script.contains(#"write text "cd '/a \"b\"\\c' && claude --resume 'id'""#), script)
        XCTAssertTrue(script.contains(#"application id "com.googlecode.iterm2""#))
    }
}

final class SessionMarksStoreTests: XCTestCase {
    func testRoundTripAndDropsEmptyMarks() throws {
        let fixture = try FixtureDirectory()
        let store = SessionMarksStore(fileURL: fixture.url("nested/marks.json"))
        XCTAssertEqual(try store.load(), [:])

        try store.save([
            "claude:a": SessionMark(pinned: true, note: "run migration"),
            "codex:b": SessionMark(pinned: nil, note: ""),
        ])

        XCTAssertEqual(try store.load(), ["claude:a": SessionMark(pinned: true, note: "run migration")])
    }

    func testExplicitUnpinIsKeptSoProviderPinDoesNotReturn() throws {
        let fixture = try FixtureDirectory()
        let store = SessionMarksStore(fileURL: fixture.url("marks.json"))

        try store.save(["codex:pinned-in-codex": SessionMark(pinned: false)])

        XCTAssertEqual(try store.load()["codex:pinned-in-codex"]?.pinned, false)
    }
}

final class SessionSearchTests: XCTestCase {
    private let session = Session(
        provider: .codex, sessionID: "1", title: "Budget tool charts",
        projectPath: "/work/projects/budget-tool", lastActivity: Date(), lastPrompt: "compare the new chart colours"
    )

    func testMatchesAllWordsAcrossFields() {
        XCTAssertTrue(SessionSearch.matches(session, note: "", query: ""))
        XCTAssertTrue(SessionSearch.matches(session, note: "", query: "budget CHART"))
        XCTAssertTrue(SessionSearch.matches(session, note: "deploy friday", query: "codex friday"))
        XCTAssertFalse(SessionSearch.matches(session, note: "", query: "webapp"))
    }
}
