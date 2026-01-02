// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "PeriscopeUIKitExample",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "PeriscopeUIKitExample",
            dependencies: [
                .product(name: "Periscope", package: "Periscope")
            ],
            path: ".",
            sources: ["AppDelegate.swift", "ViewController.swift"]
        )
    ]
)