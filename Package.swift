// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "floats",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "ssh://git.recurse.world/octavore/strudel-markdown-editor", branch: "main")

    ],
    targets: [
        .executableTarget(
            name: "floats",
            dependencies: [
                .product(name: "CharmingEditor", package: "strudel-markdown-editor")

            ],
            path: "Sources/floats"
        )
    ]
)
