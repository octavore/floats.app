// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "floats",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/octavore/crumpet", branch: "main"),
        .package(url: "https://github.com/octavore/sunshine", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "floats",
            dependencies: [
                .product(name: "Crumpet", package: "crumpet"),
                .product(name: "Sunshine", package: "sunshine"),
            ],
            path: "Sources/floats"
        )
    ]
)
