// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Nudge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nudge", targets: ["Nudge"]),
        .executable(name: "nudge-hook", targets: ["NudgeHook"]),
    ],
    dependencies: [
        // Updates, delivered through GitHub releases and verified with EdDSA.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        /// The inbox record format, shared by the collector and the app.
        .target(name: "NudgeHookSchema"),
        .target(name: "NudgeKit", dependencies: ["NudgeHookSchema"]),
        /// Tiny command Claude Code runs for each hook event. Observation only.
        .executableTarget(name: "NudgeHook", dependencies: ["NudgeHookSchema"]),
        .executableTarget(
            name: "Nudge",
            dependencies: ["NudgeKit", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Nudge.app ships Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "NudgeKitTests", dependencies: ["NudgeKit", "NudgeHookSchema"]),
    ]
)
