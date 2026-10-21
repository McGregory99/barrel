// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BarrelApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BarrelApp", targets: ["BarrelApp"]),
        .library(name: "BarrelAppKit", targets: ["BarrelAppKit"]),
    ],
    dependencies: [
        .package(path: "../barrel"),
    ],
    targets: [
        .target(name: "BarrelAppKit", dependencies: [.product(name: "BarrelCore", package: "barrel")]),
        .executableTarget(name: "BarrelApp", dependencies: ["BarrelAppKit"]),
        .testTarget(name: "BarrelAppKitTests", dependencies: ["BarrelAppKit"]),
    ],
    // BarrelCore's service types are not Sendable; the app hops them off the main actor explicitly.
    swiftLanguageModes: [.v5]
)
