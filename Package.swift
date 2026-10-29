// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tsuzuki",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tsuzuki", targets: ["Tsuzuki"]),
        .library(name: "TsuzukiCore", targets: ["TsuzukiCore"]),
    ],
    targets: [
        .target(
            name: "TsuzukiCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Tsuzuki",
            dependencies: ["TsuzukiCore"]
        ),
        .testTarget(
            name: "TsuzukiCoreTests",
            dependencies: ["TsuzukiCore"]
        ),
    ]
)
