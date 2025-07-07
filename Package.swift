// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "vox",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "vox",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: [
                "vox-performance"
            ]
        ),
        .testTarget(
            name: "voxTests",
            dependencies: ["vox"],
            resources: [
                .copy("Resources"),
                .copy("TESTING.md")
            ]
        )
    ]
)
