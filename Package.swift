// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pip", targets: ["Pip"]),
        .executable(name: "pip-hook", targets: ["PipHook"]),
    ],
    dependencies: [
        // Updates, delivered through GitHub releases and verified with EdDSA.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        /// The inbox record format, shared by the collector and the app.
        .target(name: "PipHookSchema"),
        .target(name: "PipKit", dependencies: ["PipHookSchema"]),
        /// Tiny command Claude Code runs for each hook event. Observation only.
        .executableTarget(name: "PipHook", dependencies: ["PipHookSchema"]),
        .executableTarget(
            name: "Pip",
            dependencies: ["PipKit", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Pip.app ships Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "PipKitTests", dependencies: ["PipKit", "PipHookSchema"]),
    ]
)
