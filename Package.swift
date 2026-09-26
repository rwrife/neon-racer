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
            path: "NeonRacer/Game/Simulation"
        ),
        .testTarget(
            name: "NeonRacerCoreTests",
            dependencies: ["NeonRacerCore"],
            path: "NeonRacerTests"
        )
    ]
)
