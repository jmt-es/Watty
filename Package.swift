// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Watty",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Watty", targets: ["Watty"]),
        .executable(name: "watty-cli", targets: ["watty-cli"])
    ],
    targets: [
        .target(
            name: "WattyCore",
            path: "Sources/WattyCore"
        ),
        .executableTarget(
            name: "Watty",
            dependencies: ["WattyCore"],
            path: "Sources/Watty"
        ),
        .target(
            name: "WattyCLI",
            dependencies: ["WattyCore"],
            path: "Sources/WattyCLI"
        ),
        .executableTarget(
            name: "watty-cli",
            dependencies: ["WattyCLI"],
            path: "Sources/watty-cli"
        ),
        .testTarget(
            name: "WattyCoreTests",
            dependencies: ["WattyCore"],
            path: "Tests/WattyCoreTests"
        ),
        .testTarget(
            name: "WattyAppTests",
            dependencies: ["Watty", "WattyCore"],
            path: "Tests/WattyAppTests"
        ),
        .testTarget(
            name: "WattyCLITests",
            dependencies: ["WattyCLI", "WattyCore"],
            path: "Tests/WattyCLITests"
        )
    ]
)
