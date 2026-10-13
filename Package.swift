// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StressCore",
    platforms: [.macOS(.v14), .watchOS("26.0")],
    products: [.library(name: "StressCore", targets: ["StressCore"])],
    targets: [
        .target(name: "StressCore"),
        .testTarget(name: "StressCoreTests", dependencies: ["StressCore"])
    ]
)
