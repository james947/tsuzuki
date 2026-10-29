import XCTest
@testable import SessionLauncherCore

final class WindowChooserTests: XCTestCase {
    private let windows = [
        WindowChooser.WindowTabs(id: 443, paths: ["/Users/me/work/acme/webapp", "/Users/me/work/acme/webapp"]),
        WindowChooser.WindowTabs(id: 442, paths: ["/Users/me/work/projects/notes-app", "/Users/me/work/projects/budget-tool"]),
    ]

    func testExactFolderMatch() {
        XCTAssertEqual(WindowChooser.bestWindow(for: "/Users/me/work/projects/budget-tool", among: windows), 442)
        XCTAssertEqual(WindowChooser.bestWindow(for: "/Users/me/work/acme/webapp", among: windows), 443)
    }

    func testClosestParentFolderWins() {
        XCTAssertEqual(WindowChooser.bestWindow(for: "/Users/me/work/projects/brand-new", among: windows), 442)
        XCTAssertEqual(WindowChooser.bestWindow(for: "/Users/me/work/acme/webapp/server", among: windows), 443)
    }

    func testTieOrNoWindowsFallsBackToFrontmost() {
        XCTAssertNil(WindowChooser.bestWindow(for: "/Users/me/Desktop/notes", among: windows))
        XCTAssertNil(WindowChooser.bestWindow(for: "/Users/me/work/projects/x", among: []))
        XCTAssertNil(WindowChooser.bestWindow(for: "/opt/elsewhere", among: windows))
    }

    func testIgnoresTrailingSlashesAndDotSegments() {
        XCTAssertEqual(WindowChooser.bestWindow(for: "/Users/me/work/projects/photo-sorter/", among: windows), 442)
        XCTAssertEqual(WindowChooser.bestWindow(for: "/Users/me/work/acme/./webapp", among: windows), 443)
    }

    func testParsesScriptOutputInWindowOrder() {
        let output = "443\t/a/webapp\n442\t/b/one\n443\t/a/webapp two\nbad line\n442\t\n"

        XCTAssertEqual(WindowChooser.parse(output), [
            WindowChooser.WindowTabs(id: 443, paths: ["/a/webapp", "/a/webapp two"]),
            WindowChooser.WindowTabs(id: 442, paths: ["/b/one"]),
        ])
    }

    func testOpenTabScriptTargetsWindow() {
        let script = ITermScript.openTab(running: "echo hi", inWindowID: 442)
        XCTAssertTrue(script.contains("set targetWindow to window id 442"))
        XCTAssertFalse(ITermScript.openTab(running: "echo hi").contains("window id"))
    }
}
