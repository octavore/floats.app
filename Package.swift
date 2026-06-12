// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "journal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "journal",
            path: "Sources/journal"
        ),
    ]
)
