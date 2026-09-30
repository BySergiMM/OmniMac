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
        // Átomos de C11 (release/acquire) para pasar datos entre hilos sin cerrojos:
        // `Synchronization.Atomic` pide macOS 15 y aquí se compila para 14.2. Son
        // unas decenas de líneas propias, sin paquete nuevo. Ver CAtomics.h.
        .target(name: "CAtomics"),
        .executableTarget(
            name: "OmniMac",
            dependencies: [
                "CAtomics",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "OmniMacTests",
            dependencies: ["OmniMac"]
        ),
    ]
)
