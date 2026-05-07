// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClaudeUsageApp", targets: ["ClaudeUsageApp"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsageApp",
            path: "Sources/ClaudeUsageApp",
            resources: [],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ClaudeUsageAppTests",
            dependencies: ["ClaudeUsageApp"],
            path: "Tests/ClaudeUsageAppTests"
        )
    ]
)
