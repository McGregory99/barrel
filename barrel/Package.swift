// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "barrel",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "barrel", targets: ["barrel"]),
        .library(name: "BarrelCore", targets: ["BarrelCore"]),
        .library(name: "BarrelRecipes", targets: ["BarrelRecipes"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "BarrelCore"),
        .target(name: "BarrelRecipes", dependencies: ["BarrelCore"]),
        .executableTarget(
            name: "barrel",
            dependencies: [
                "BarrelCore",
                "BarrelRecipes",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "BarrelCoreTests", dependencies: ["BarrelCore"]),
        .testTarget(name: "BarrelRecipesTests", dependencies: ["BarrelRecipes"]),
    ]
)
