import Foundation

enum DifficultyProfile: String, CaseIterable, Codable, Sendable {
    case novice
    case standard
    case expert
}

enum RaceRank: String, CaseIterable, Codable, Sendable {
    case unranked
    case bronze
    case silver
    case gold
}

struct TrafficBalance: Equatable, Sendable {
    let baseDensity: Double
    let randomVariation: Double
    let raceProgressIncrease: Double
    /// Enables runtime traffic/obstacle spawning. Balance scripts can disable this
    /// to preserve collision-free representative rank runs while gameplay defaults on.
    let isEnabled: Bool

    init(
        baseDensity: Double,
        randomVariation: Double,
        raceProgressIncrease: Double,
        isEnabled: Bool = true
    ) {
        self.baseDensity = baseDensity
        self.randomVariation = randomVariation
        self.raceProgressIncrease = raceProgressIncrease
        self.isEnabled = isEnabled
    }

    func density(progress: Double, randomUnitValue: Double) -> Double {
        baseDensity
            + raceProgressIncrease * clamped(progress, to: 0...1)
            + randomVariation * clamped(randomUnitValue, to: 0...1)
    }

    var maximumDensity: Double {
        baseDensity + randomVariation + raceProgressIncrease
    }

    func withSpawningEnabled(_ enabled: Bool) -> TrafficBalance {
        TrafficBalance(
            baseDensity: baseDensity,
            randomVariation: randomVariation,
            raceProgressIncrease: raceProgressIncrease,
            isEnabled: enabled
        )
    }
}

struct CrashPenaltyBalance: Equatable, Sendable {
    let trafficTimePenalty: TimeInterval
    let obstacleTimePenalty: TimeInterval
    let roadsideHazardTimePenalty: TimeInterval

    static let standard = CrashPenaltyBalance(
        trafficTimePenalty: 3,
        obstacleTimePenalty: 2,
        roadsideHazardTimePenalty: 3
    )

    static let novice = CrashPenaltyBalance(
        trafficTimePenalty: 2,
        obstacleTimePenalty: 1,
        roadsideHazardTimePenalty: 2
    )

    static let expert = CrashPenaltyBalance(
        trafficTimePenalty: 3.5,
        obstacleTimePenalty: 2.5,
        roadsideHazardTimePenalty: 3.5
    )
}


struct DrivingBalance: Equatable, Sendable {
    let lateralLimit: Double
    let centrifugalForce: Double
    let steeringAtRestRatio: Double
    let offRoadSpeedLimitRatio: Double
    let offRoadDrag: Double
    let offRoadGripRatio: Double
    let wallSpeedLossPerSecond: Double
    let gradeAccelerationScale: Double
    let crashSteeringRatio: Double
    let driftSteeringMultiplier: Double
    let driftSpeedLossPerSecond: Double
    let driftMinimumSpeedRatio: Double
    let driftCurveSpeedRatio: Double
    let driftHardSteerThreshold: Double
    let driftExitSteerThreshold: Double
    let driftBrakeTapThreshold: Double
    let driftCurveThreshold: Double
    let maximumDriftSlipAngle: Double
    let headingSteeringAngle: Double
    let slipResponse: Double

    static let standard = DrivingBalance(
        lateralLimit: 1.45,
        centrifugalForce: 0.000_12,
        steeringAtRestRatio: 0.22,
        offRoadSpeedLimitRatio: 0.55,
        offRoadDrag: 55,
        offRoadGripRatio: 0.58,
        wallSpeedLossPerSecond: 70,
        gradeAccelerationScale: 38,
        crashSteeringRatio: 0.35,
        driftSteeringMultiplier: 1.28,
        driftSpeedLossPerSecond: 9,
        driftMinimumSpeedRatio: 0.58,
        driftCurveSpeedRatio: 0.8,
        driftHardSteerThreshold: 0.72,
        driftExitSteerThreshold: 0.34,
        driftBrakeTapThreshold: 0.18,
        driftCurveThreshold: 0.18,
        maximumDriftSlipAngle: 0.35,
        headingSteeringAngle: 0.18,
        slipResponse: 8
    )

    static let novice = DrivingBalance(
        lateralLimit: standard.lateralLimit,
        centrifugalForce: 0.000_105,
        steeringAtRestRatio: 0.28,
        offRoadSpeedLimitRatio: 0.6,
        offRoadDrag: 48,
        offRoadGripRatio: 0.65,
        wallSpeedLossPerSecond: 58,
        gradeAccelerationScale: 32,
        crashSteeringRatio: 0.45,
        driftSteeringMultiplier: 1.22,
        driftSpeedLossPerSecond: 7,
        driftMinimumSpeedRatio: 0.55,
        driftCurveSpeedRatio: 0.78,
        driftHardSteerThreshold: 0.68,
        driftExitSteerThreshold: 0.3,
        driftBrakeTapThreshold: 0.16,
        driftCurveThreshold: 0.16,
        maximumDriftSlipAngle: standard.maximumDriftSlipAngle,
        headingSteeringAngle: standard.headingSteeringAngle,
        slipResponse: standard.slipResponse
    )

    static let expert = DrivingBalance(
        lateralLimit: standard.lateralLimit,
        centrifugalForce: 0.000_13,
        steeringAtRestRatio: 0.2,
        offRoadSpeedLimitRatio: 0.52,
        offRoadDrag: 62,
        offRoadGripRatio: 0.55,
        wallSpeedLossPerSecond: 78,
        gradeAccelerationScale: 42,
        crashSteeringRatio: 0.32,
        driftSteeringMultiplier: 1.32,
        driftSpeedLossPerSecond: 10,
        driftMinimumSpeedRatio: 0.6,
        driftCurveSpeedRatio: 0.82,
        driftHardSteerThreshold: 0.74,
        driftExitSteerThreshold: 0.36,
        driftBrakeTapThreshold: 0.2,
        driftCurveThreshold: 0.2,
        maximumDriftSlipAngle: standard.maximumDriftSlipAngle,
        headingSteeringAngle: standard.headingSteeringAngle,
        slipResponse: standard.slipResponse
    )
}

struct BoostEconomy: Equatable, Sendable {
    let capacity: TimeInterval
    let initialCharge: TimeInterval
    let consumptionPerSecond: Double
    let rechargePerSecond: Double
    let accelerationBonus: Double
    let maximumSpeedMultiplier: Double
}

struct ScoringBalance: Equatable, Sendable {
    let pointsPerDistance: Double
    let pointsPerBoostSecond: Double
    let bronzeThreshold: Double
    let silverThreshold: Double
    let goldThreshold: Double

    func rank(for score: Double) -> RaceRank {
        switch score {
        case goldThreshold...:
            return .gold
        case silverThreshold...:
            return .silver
        case bronzeThreshold...:
            return .bronze
        default:
            return .unranked
        }
    }
}

enum RaceConfigurationValidationError: Error, Equatable, CustomStringConvertible {
    case nonFiniteOrNonPositive(String)
    case nonFiniteOrNegative(String)
    case valueOutsideUnitRange(String)
    case maximumFrameDeltaSmallerThanFixedTimeStep
    case initialBoostExceedsCapacity
    case boostSpeedMultiplierNotGreaterThanOne
    case rankThresholdsNotStrictlyIncreasing
    case goldRankThresholdUnreachable
    case stageCannotBeCompletedWithinTimeLimit

    var description: String {
        switch self {
        case .nonFiniteOrNonPositive(let field):
            return "\(field) must be finite and greater than zero"
        case .nonFiniteOrNegative(let field):
            return "\(field) must be finite and nonnegative"
        case .valueOutsideUnitRange(let field):
            return "\(field) must be between zero and one"
        case .maximumFrameDeltaSmallerThanFixedTimeStep:
            return "maximumFrameDelta must be at least fixedTimeStep"
        case .initialBoostExceedsCapacity:
            return "boost.initialCharge must not exceed boost.capacity"
        case .boostSpeedMultiplierNotGreaterThanOne:
            return "boost.maximumSpeedMultiplier must be greater than one"
        case .rankThresholdsNotStrictlyIncreasing:
            return "score rank thresholds must be strictly increasing"
        case .goldRankThresholdUnreachable:
            return "gold rank threshold exceeds the theoretical maximum score"
        case .stageCannotBeCompletedWithinTimeLimit:
            return "stageLength must be reachable at maximumSpeed within raceDuration"
        }
    }
}

extension RaceConfiguration {
    static let novice = RaceConfiguration(
        fixedTimeStep: 1.0 / 120.0,
        maximumFrameDelta: 0.25,
        maximumSimulationStepsPerFrame: 12,
        acceleration: 44,
        braking: 62,
        drag: 9,
        maximumSpeed: 112,
        steeringRate: 1.65,
        driving: .novice,
        crashPenalties: .novice,
        stageLength: 4_500,
        raceDuration: 100,
        profile: .novice,
        traffic: TrafficBalance(
            baseDensity: 0.14,
            randomVariation: 0.08,
            raceProgressIncrease: 0.08
        ),
        boost: BoostEconomy(
            capacity: 7,
            initialCharge: 7,
            consumptionPerSecond: 1,
            rechargePerSecond: 0.45,
            accelerationBonus: 18,
            maximumSpeedMultiplier: 1.18
        ),
        scoring: ScoringBalance(
            pointsPerDistance: 1,
            pointsPerBoostSecond: 18,
            bronzeThreshold: 5_200,
            silverThreshold: 5_400,
            goldThreshold: 5_550
        )
    )

    static let expert = RaceConfiguration(
        fixedTimeStep: 1.0 / 120.0,
        maximumFrameDelta: 0.25,
        maximumSimulationStepsPerFrame: 12,
        acceleration: 40,
        braking: 68,
        drag: 11,
        maximumSpeed: 128,
        steeringRate: 2,
        driving: .expert,
        crashPenalties: .expert,
        stageLength: 5_500,
        raceDuration: 84,
        profile: .expert,
        traffic: TrafficBalance(
            baseDensity: 0.28,
            randomVariation: 0.14,
            raceProgressIncrease: 0.14
        ),
        boost: BoostEconomy(
            capacity: 5,
            initialCharge: 3,
            consumptionPerSecond: 1.15,
            rechargePerSecond: 0.2,
            accelerationBonus: 24,
            maximumSpeedMultiplier: 1.22
        ),
        scoring: ScoringBalance(
            pointsPerDistance: 1,
            pointsPerBoostSecond: 35,
            bronzeThreshold: 6_200,
            silverThreshold: 6_375,
            goldThreshold: 6_525
        )
    )

    static func configuration(for profile: DifficultyProfile) -> RaceConfiguration {
        switch profile {
        case .novice:
            return .novice
        case .standard:
            return .standard
        case .expert:
            return .expert
        }
    }

    var validationErrors: [RaceConfigurationValidationError] {
        var errors: [RaceConfigurationValidationError] = []

        let positiveValues: [(String, Double)] = [
            ("fixedTimeStep", fixedTimeStep),
            ("maximumFrameDelta", maximumFrameDelta),
            ("acceleration", acceleration),
            ("braking", braking),
            ("drag", drag),
            ("maximumSpeed", maximumSpeed),
            ("steeringRate", steeringRate),
            ("driving.lateralLimit", driving.lateralLimit),
            ("driving.centrifugalForce", driving.centrifugalForce),
            ("driving.offRoadDrag", driving.offRoadDrag),
            ("driving.wallSpeedLossPerSecond", driving.wallSpeedLossPerSecond),
            ("driving.gradeAccelerationScale", driving.gradeAccelerationScale),
            ("driving.driftSteeringMultiplier", driving.driftSteeringMultiplier),
            ("driving.driftSpeedLossPerSecond", driving.driftSpeedLossPerSecond),
            ("driving.maximumDriftSlipAngle", driving.maximumDriftSlipAngle),
            ("driving.headingSteeringAngle", driving.headingSteeringAngle),
            ("driving.slipResponse", driving.slipResponse),
            ("crashPenalties.trafficTimePenalty", crashPenalties.trafficTimePenalty),
            ("crashPenalties.obstacleTimePenalty", crashPenalties.obstacleTimePenalty),
            ("crashPenalties.roadsideHazardTimePenalty", crashPenalties.roadsideHazardTimePenalty),
            ("stageLength", stageLength),
            ("raceDuration", raceDuration),
            ("boost.capacity", boost.capacity),
            ("boost.consumptionPerSecond", boost.consumptionPerSecond),
            ("boost.accelerationBonus", boost.accelerationBonus),
            ("boost.maximumSpeedMultiplier", boost.maximumSpeedMultiplier),
            ("scoring.pointsPerDistance", scoring.pointsPerDistance),
            ("scoring.pointsPerBoostSecond", scoring.pointsPerBoostSecond)
        ]
        for (field, value) in positiveValues where !value.isFinite || value <= 0 {
            errors.append(.nonFiniteOrNonPositive(field))
        }

        if maximumSimulationStepsPerFrame <= 0 {
            errors.append(.nonFiniteOrNonPositive("maximumSimulationStepsPerFrame"))
        }
        if maximumFrameDelta < fixedTimeStep {
            errors.append(.maximumFrameDeltaSmallerThanFixedTimeStep)
        }

        let unitValues: [(String, Double)] = [
            ("traffic.baseDensity", traffic.baseDensity),
            ("traffic.randomVariation", traffic.randomVariation),
            ("traffic.raceProgressIncrease", traffic.raceProgressIncrease),
            ("driving.steeringAtRestRatio", driving.steeringAtRestRatio),
            ("driving.offRoadSpeedLimitRatio", driving.offRoadSpeedLimitRatio),
            ("driving.offRoadGripRatio", driving.offRoadGripRatio),
            ("driving.crashSteeringRatio", driving.crashSteeringRatio),
            ("driving.driftMinimumSpeedRatio", driving.driftMinimumSpeedRatio),
            ("driving.driftCurveSpeedRatio", driving.driftCurveSpeedRatio),
            ("driving.driftHardSteerThreshold", driving.driftHardSteerThreshold),
            ("driving.driftExitSteerThreshold", driving.driftExitSteerThreshold),
            ("driving.driftBrakeTapThreshold", driving.driftBrakeTapThreshold),
            ("driving.driftCurveThreshold", driving.driftCurveThreshold)
        ]
        for (field, value) in unitValues where !value.isFinite || !(0...1).contains(value) {
            errors.append(.valueOutsideUnitRange(field))
        }

        if !boost.initialCharge.isFinite || boost.initialCharge < 0 {
            errors.append(.nonFiniteOrNegative("boost.initialCharge"))
        } else if boost.initialCharge > boost.capacity {
            errors.append(.initialBoostExceedsCapacity)
        }

        if !boost.rechargePerSecond.isFinite || boost.rechargePerSecond < 0 {
            errors.append(.nonFiniteOrNegative("boost.rechargePerSecond"))
        }
        if boost.maximumSpeedMultiplier.isFinite, boost.maximumSpeedMultiplier <= 1 {
            errors.append(.boostSpeedMultiplierNotGreaterThanOne)
        }

        let ranks = [
            scoring.bronzeThreshold,
            scoring.silverThreshold,
            scoring.goldThreshold
        ]
        if ranks.contains(where: { !$0.isFinite || $0 <= 0 })
            || !(ranks[0] < ranks[1] && ranks[1] < ranks[2]) {
            errors.append(.rankThresholdsNotStrictlyIncreasing)
        }

        let theoreticalBoostTime = min(
            raceDuration,
            (boost.initialCharge + boost.rechargePerSecond * raceDuration)
                / (boost.consumptionPerSecond + boost.rechargePerSecond)
        )
        let theoreticalMaximumScore =
            stageLength * scoring.pointsPerDistance
            + theoreticalBoostTime * scoring.pointsPerBoostSecond
            + arcadeScoring.finishPoints
            + arcadeScoring.checkpointPoints * 2
        if scoring.goldThreshold.isFinite,
           theoreticalMaximumScore.isFinite,
           scoring.goldThreshold > theoreticalMaximumScore {
            errors.append(.goldRankThresholdUnreachable)
        }

        if maximumSpeed.isFinite, raceDuration.isFinite,
           stageLength > maximumSpeed * boost.maximumSpeedMultiplier * raceDuration {
            errors.append(.stageCannotBeCompletedWithinTimeLimit)
        }

        return errors
    }
}

private func clamped<T: Comparable>(_ value: T, to limits: ClosedRange<T>) -> T {
    min(max(value, limits.lowerBound), limits.upperBound)
}
