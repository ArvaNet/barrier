// swift-tools-version:5.9
// Pure-Swift core: models, schedule engine, reminder planning, guidance text.
// Foundation only, so it builds and tests on Linux as well as Apple platforms.
import PackageDescription

let package = Package(
    name: "BarrierCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BarrierCore", targets: ["BarrierCore"]),
    ],
    targets: [
        .target(name: "BarrierCore"),
        .testTarget(name: "BarrierCoreTests", dependencies: ["BarrierCore"]),
    ]
)
