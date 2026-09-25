// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Peeku",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Peeku", targets: ["Peeku"]),
        .executable(name: "peeku-hook", targets: ["PeekuHook"]),
    ],
    dependencies: [
        // Updates, delivered through GitHub releases and verified with EdDSA.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        /// The inbox record format, shared by the collector and the app.
        .target(name: "PeekuHookSchema"),
        .target(name: "PeekuKit", dependencies: ["PeekuHookSchema"]),
        /// Tiny command Claude Code runs for each hook event. Observation only.
        .executableTarget(name: "PeekuHook", dependencies: ["PeekuHookSchema"]),
        .executableTarget(
            name: "Peeku",
            dependencies: ["PeekuKit", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Peeku.app ships Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "PeekuKitTests", dependencies: ["PeekuKit", "PeekuHookSchema"]),
    ]
)
