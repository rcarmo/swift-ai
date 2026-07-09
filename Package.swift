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
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(name: "SwiftAI", dependencies: [.product(name: "Crypto", package: "swift-crypto"), "CZstd"]),
        .systemLibrary(name: "CZstd", pkgConfig: "libzstd", providers: [.apt(["libzstd-dev"]), .brew(["zstd"])]),
        .testTarget(name: "SwiftAITests", dependencies: ["SwiftAI"])
    ]
)
