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
    let profile: DifficultyProfile
    let traffic: TrafficBalance
    let boost: BoostEconomy
    let scoring: ScoringBalance

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
        raceDuration: 90,
        profile: .standard,
        traffic: TrafficBalance(
            baseDensity: 0.2,
            randomVariation: 0.12,
            raceProgressIncrease: 0.1
        ),
        boost: BoostEconomy(
            capacity: 6,
            initialCharge: 4,
            consumptionPerSecond: 1,
            rechargePerSecond: 0.3,
            accelerationBonus: 21,
            maximumSpeedMultiplier: 1.2
        ),
        scoring: ScoringBalance(
            pointsPerDistance: 1,
            pointsPerBoostSecond: 25,
            bronzeThreshold: 4_900,
            silverThreshold: 5_080,
            goldThreshold: 5_250
        )
    )
}
