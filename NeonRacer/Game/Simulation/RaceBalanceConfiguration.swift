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

    func density(progress: Double, randomUnitValue: Double) -> Double {
        baseDensity
            + raceProgressIncrease * progress.clamped(to: 0...1)
            + randomVariation * randomUnitValue.clamped(to: 0...1)
    }

    var maximumDensity: Double {
        baseDensity + randomVariation + raceProgressIncrease
    }
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
            bronzeThreshold: 4_400,
            silverThreshold: 4_600,
            goldThreshold: 4_750
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
            bronzeThreshold: 5_400,
            silverThreshold: 5_575,
            goldThreshold: 5_725
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
            ("traffic.raceProgressIncrease", traffic.raceProgressIncrease)
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

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
