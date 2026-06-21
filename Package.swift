// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-ai",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "SwiftAI", targets: ["SwiftAI"])
    ],
    targets: [
        .target(name: "SwiftAI"),
        .testTarget(name: "SwiftAITests", dependencies: ["SwiftAI"])
    ]
)
