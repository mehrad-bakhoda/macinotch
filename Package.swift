// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacInotch",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared so the unprivileged app and the root helper use identical
        // SMC plumbing rather than two drifting copies.
        .target(
            name: "SMCKit",
            path: "Sources/SMCKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "notchfand",
            dependencies: ["SMCKit"],
            path: "Sources/notchfand",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MacInotch",
            dependencies: ["SMCKit"],
            path: "Sources/MacInotch",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "notchctl",
            path: "Sources/notchctl",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
