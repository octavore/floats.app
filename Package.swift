// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "floats",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.8.0"),
        .package(
            url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown",
            from: "0.5.3"),
    ],
    targets: [
        .executableTarget(
            name: "floats",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
            ],
            path: "Sources/floats"
        ),
        .testTarget(
            name: "floatsTests",
            dependencies: ["floats"],
            path: "Tests/floatsTests"
        ),
    ]
)
