// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SoccerShared",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "SoccerShared",
            targets: ["SoccerShared"]
        ),
    ],
    targets: [
        .target(
            name: "SoccerShared",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SoccerSharedTests",
            dependencies: ["SoccerShared"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
