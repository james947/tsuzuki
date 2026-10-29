import SwiftUI

@main
struct SessionLauncherApp: App {
    @StateObject private var model = LauncherModel()

    var body: some Scene {
        MenuBarExtra {
            LauncherView()
                .environmentObject(model)
        } label: {
            Image(systemName: "bubble.left.and.text.bubble.right")
        }
        .menuBarExtraStyle(.window)
    }
}
