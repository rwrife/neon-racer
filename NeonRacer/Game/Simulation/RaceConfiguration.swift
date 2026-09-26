import Foundation

struct RaceConfiguration: Equatable, Sendable {
    let fixedTimeStep: TimeInterval
    let maximumFrameDelta: TimeInterval
    let maximumSimulationStepsPerFrame: Int
    let acceleration: Double
    let braking: Double
    let drag: Double
    let maximumSpeed: Double
    let steeringRate: Double
    let stageLength: Double
    let raceDuration: TimeInterval

    static let standard = RaceConfiguration(
        fixedTimeStep: 1.0 / 120.0,
        maximumFrameDelta: 0.25,
        maximumSimulationStepsPerFrame: 12,
        acceleration: 42,
        braking: 64,
        drag: 10,
        maximumSpeed: 120,
        steeringRate: 1.8,
        stageLength: 5_000,
        raceDuration: 90
    )
}

