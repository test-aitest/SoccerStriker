// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WebSceneKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "WebSceneKit",
            targets: ["WebSceneKit"]
        )
    ],
    targets: [
        .target(
            name: "WebSceneKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "WebSceneKitTests",
            dependencies: ["WebSceneKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
