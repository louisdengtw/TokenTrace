// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenTraceApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TokenTraceApp", targets: ["TokenTraceApp"])
    ],
    targets: [
        .executableTarget(
            name: "TokenTraceApp",
            path: "Sources/TokenTraceApp",
            resources: [],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "TokenTraceAppTests",
            dependencies: ["TokenTraceApp"],
            path: "Tests/TokenTraceAppTests"
        )
    ]
)
