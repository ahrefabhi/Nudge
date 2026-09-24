// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pip", targets: ["Pip"]),
        .executable(name: "pip-hook", targets: ["PipHook"]),
    ],
    targets: [
        /// The inbox record format, shared by the collector and the app.
        .target(name: "PipHookSchema"),
        .target(name: "PipKit", dependencies: ["PipHookSchema"]),
        /// Tiny command Claude Code runs for each hook event. Observation only.
        .executableTarget(name: "PipHook", dependencies: ["PipHookSchema"]),
        .executableTarget(
            name: "Pip",
            dependencies: ["PipKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "PipKitTests", dependencies: ["PipKit", "PipHookSchema"]),
    ]
)
