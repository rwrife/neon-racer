// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NeonRacerCore",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "NeonRacerCore", targets: ["NeonRacerCore"])
    ],
    targets: [
        .target(
            name: "NeonRacerCore",
            path: "NeonRacer",
            exclude: [
                "App",
                "Content",
                "Features",
                "Game/Rendering",
                "Resources",
                "Services",
                "Shared/Accessibility/AccessibilitySettingsStore.swift",
                "Shared/Design/NeonPalette.swift"
            ],
            sources: [
                "Game/Simulation",
                "Shared/Accessibility/AccessibilitySettings.swift",
                "Shared/Design/AccessiblePalette.swift"
            ]
        ),
        .testTarget(
            name: "NeonRacerCoreTests",
            dependencies: ["NeonRacerCore"],
            path: "NeonRacerTests"
        )
    ]
)
