// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SessionLauncher",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SessionLauncher", targets: ["SessionLauncher"]),
        .library(name: "SessionLauncherCore", targets: ["SessionLauncherCore"]),
    ],
    targets: [
        .target(
            name: "SessionLauncherCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "SessionLauncher",
            dependencies: ["SessionLauncherCore"]
        ),
        .testTarget(
            name: "SessionLauncherCoreTests",
            dependencies: ["SessionLauncherCore"]
        ),
    ]
)
