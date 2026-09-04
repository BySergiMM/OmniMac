// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OmniMac",
    platforms: [
        .macOS("14.2")
    ],
    dependencies: [
        // Actualizaciones automáticas (appcast en GitHub Releases).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "OmniMac",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "OmniMacTests",
            dependencies: ["OmniMac"]
        ),
    ]
)
