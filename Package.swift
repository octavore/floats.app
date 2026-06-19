// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "journal",
    platforms: [.macOS(.v14), .iOS(.v18)],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.8.0"),
        .package(
            url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown",
            from: "0.5.3"),
    ],
    targets: [
        .executableTarget(
            name: "journal",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
            ],
            path: "Sources/journal"
        ),
        .testTarget(
            name: "journalTests",
            dependencies: ["journal"],
            path: "Tests/journalTests"
        ),
    ]
)
