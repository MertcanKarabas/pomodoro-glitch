// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpiderCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SpiderCore", targets: ["SpiderCore"]),
    ],
    targets: [
        .target(name: "SpiderCore"),
        .testTarget(name: "SpiderCoreTests", dependencies: ["SpiderCore"]),
    ]
)
