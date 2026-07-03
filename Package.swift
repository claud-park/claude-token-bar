// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeTokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeTokenBar",
            path: "Sources/ClaudeTokenBar"
        ),
        .testTarget(
            name: "ClaudeTokenBarTests",
            dependencies: ["ClaudeTokenBar"],
            path: "Tests/ClaudeTokenBarTests"
        )
    ]
)
