// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NeonRacerCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v13)
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
                "Features",
                "Game/Rendering",
                "Game/Rendering3D",
                "Resources",
                "Services/Audio",
                "Services/Haptics",
                "Services/Input",
                "Shared/Accessibility/AccessibilitySettingsStore.swift",
                "Shared/Design/NeonPalette.swift"
            ],
            sources: [
                "Content/ContentValidation.swift",
                "Content/InitialRouteContent.swift",
                "Content/StageContentLoader.swift",
                "Content/StageDefinition.swift",
                "Game/Simulation",
                "Services/Persistence",
                "Shared/Accessibility/AccessibilitySettings.swift",
                "Shared/Design/AccessiblePalette.swift"
            ],
            resources: [
                .process("Content/Fixtures")
            ]
        ),
        .testTarget(
            name: "NeonRacerCoreTests",
            dependencies: ["NeonRacerCore"],
            path: "NeonRacerTests"
        )
    ]
)
