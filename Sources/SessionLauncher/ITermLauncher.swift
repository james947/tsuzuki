import AppKit
import SessionLauncherCore

enum ITermLauncher {
    struct Failure: Error {
        let message: String
    }

    /// Runs on the main thread: NSAppleScript is not thread-safe.
    @MainActor
    static func open(_ session: Session) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: session.projectPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw Failure(message: "The project folder no longer exists:\n\(session.projectPath)")
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: ITermScript.bundleIdentifier) != nil else {
            throw Failure(message: "iTerm is not installed, so the session can't be opened.")
        }

        let command: String
        do {
            command = try ResumeCommand.make(for: session)
        } catch {
            throw Failure(message: String(describing: error))
        }

        let windowID = matchingWindow(for: session.projectPath)
        var errorInfo: NSDictionary?
        NSAppleScript(source: ITermScript.openTab(running: command, inWindowID: windowID))?
            .executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw Failure(message: describe(errorInfo))
        }
    }

    /// The open iTerm window with tabs closest to the project folder. Returns nil when iTerm
    /// isn't running (so it isn't launched just to ask) or no window clearly matches.
    @MainActor
    private static func matchingWindow(for projectPath: String) -> Int? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: ITermScript.bundleIdentifier).isEmpty
        else { return nil }
        var errorInfo: NSDictionary?
        guard let output = NSAppleScript(source: ITermScript.listTabPaths())?
            .executeAndReturnError(&errorInfo).stringValue
        else { return nil }
        return WindowChooser.bestWindow(for: projectPath, among: WindowChooser.parse(output))
    }

    private static func describe(_ info: NSDictionary) -> String {
        let code = info[NSAppleScript.errorNumber] as? Int
        if code == -1743 {
            return "Session Launcher isn't allowed to control iTerm. Turn it on in System Settings › Privacy & Security › Automation, then try again."
        }
        let message = info[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        return "iTerm couldn't open the session: \(message)" + (code.map { " (\($0))" } ?? "")
    }
}
