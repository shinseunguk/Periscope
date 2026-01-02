// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "PeriscopeSwiftUIExample",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    dependencies: [
        .package(name: "Periscope", path: "..")
    ],
    targets: [
        .executableTarget(
            name: "PeriscopeSwiftUIExample",
            dependencies: [
                .product(name: "Periscope", package: "Periscope")
            ],
            path: ".",
            sources: ["PeriscopeSwiftUIExampleApp.swift", "ContentView.swift"]
        )
    ]
)