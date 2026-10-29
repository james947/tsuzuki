import Foundation

public enum ITermScript {
    public static let bundleIdentifier = "com.googlecode.iterm2"

    private static var app: String { "application id \(quote(bundleIdentifier))" }

    /// Lists each tab's current folder as `windowID<TAB>path` lines, frontmost window first.
    /// Only run this while iTerm is already running, so it never launches iTerm by itself.
    public static func listTabPaths() -> String {
        """
        tell \(app)
            set output to ""
            repeat with aWindow in windows
                set windowID to id of aWindow
                repeat with aTab in tabs of aWindow
                    try
                        tell current session of aTab to set tabPath to (variable named "session.path")
                        if tabPath is not missing value and tabPath is not "" then
                            set output to output & windowID & tab & tabPath & linefeed
                        end if
                    end try
                end repeat
            end repeat
            return output
        end tell
        """
    }

    /// AppleScript that opens a new iTerm tab (or a window if none is open) and types
    /// `command` into its login shell, so the user's PATH (nvm, ~/.local/bin) applies.
    /// With `windowID`, the tab is added to that window when it still exists; otherwise
    /// to the frontmost window.
    public static func openTab(running command: String, inWindowID windowID: Int? = nil) -> String {
        let chooseWindow = windowID.map { id in
            """
                    try
                        set targetWindow to window id \(id)
                    end try
            """
        } ?? ""
        return """
            set wasRunning to \(app) is running
            tell \(app)
                activate
                if not wasRunning then
                    repeat 30 times
                        if (count of windows) > 0 then exit repeat
                        delay 0.1
                    end repeat
                end if
                if (count of windows) is 0 then
                    create window with default profile
                    set targetSession to current session of current window
                else if not wasRunning then
                    set targetSession to current session of current window
                else
                    set targetWindow to current window
            \(chooseWindow)
                    tell targetWindow
                        select
                        set newTab to (create tab with default profile)
                    end tell
                    set targetSession to current session of newTab
                end if
                tell targetSession to write text \(quote(command))
            end tell
            """
    }

    public static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
