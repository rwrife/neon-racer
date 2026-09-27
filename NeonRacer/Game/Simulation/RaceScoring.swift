import Foundation

struct ArcadeScoringBalance: Equatable, Sendable {
    let highSpeedThresholdRatio = 0.7
    let highSpeedPointsPerSecond = 1.5
    let overtakePoints = 120.0
    let nearMissBasePoints = 80.0
    let nearMissRiskPoints = 120.0
    let driftPointsPerSecond = 45.0
    let checkpointPoints = 150.0
    let checkpointPointsPerSecond = 25.0
    let positionPointsPerPlace = 50.0
    let finishPoints = 500.0
    let finishPositionPointsPerPlace = 125.0
    let collisionPenalty = 100.0
    let collisionSeverityPenalty = 300.0
    let activationCost = 0.2
    let collisionBoostLoss = 0.75
    let collisionBoostCooldown: TimeInterval = 1.25

    static let standard = ArcadeScoringBalance()
}

enum ScoreSource: String, CaseIterable, Codable, Sendable {
    case distance
    case speed
    case boost
    case overtake
    case nearMiss
    case drift
    case checkpoint
    case position
    case finish
    case collision
}

enum GameplayScoreEvent: Equatable, Codable, Sendable {
    case overtake(id: UInt64)
    case nearMiss(id: UInt64, proximity: Double)
    case drift(id: UInt64, duration: TimeInterval, intensity: Double)
    case checkpoint(id: UInt64, secondsUnderPar: TimeInterval)
    case position(place: Int)
    case collision(id: UInt64, severity: Double)
    case finish(position: Int?)
}

struct ScoreEvent: Equatable, Codable, Sendable {
    let sequence: Int
    let time: TimeInterval
    let source: ScoreSource
    let basePoints: Double
    let multiplier: Double
    let points: Double
    let totalAfter: Double
}

struct ScoreBreakdownEntry: Equatable, Codable, Sendable {
    let source: ScoreSource
    let eventCount: Int
    let basePoints: Double
    let awardedPoints: Double
}

struct ScoreResult: Equatable, Codable, Sendable {
    let score: Double
    let rank: RaceRank
    let breakdown: [ScoreBreakdownEntry]
}

struct ComboState: Equatable, Codable, Sendable {
    var chainCount = 0
    var multiplier = 1.0
    var timeSinceSkill: TimeInterval = 0
    var slowDrivingTime: TimeInterval = 0
}

enum BoostState: String, Equatable, Codable, Sendable {
    case unavailable
    case starting
    case active
    case ending
}

enum RaceFeedbackCue: String, Equatable, Codable, Sendable {
    case scoreAwarded
    case comboIncreased
    case comboDecayed
    case comboBroken
    case boostEarned
    case boostStarting
    case boostActive
    case boostEnding
    case boostUnavailable
    case collisionPenalty
    case nearMiss
    case overtake
    case crash
    case obstacleHit
    case timePenalty
    case rankChanged
}

enum RaceFeedbackChannel: String, Equatable, Codable, Sendable {
    case hud
    case audio
    case particle
    case haptic
}

struct RaceFeedbackEvent: Equatable, Codable, Sendable {
    let time: TimeInterval
    let cue: RaceFeedbackCue
    let channels: [RaceFeedbackChannel]
}

extension ScoreInputs {
    mutating func add(_ points: Double, source: ScoreSource) {
        switch source {
        case .distance: distancePoints += points
        case .speed: speedPoints += points
        case .boost: boostPoints += points
        case .overtake: overtakePoints += points
        case .nearMiss: nearMissPoints += points
        case .drift: driftPoints += points
        case .checkpoint: checkpointPoints += points
        case .position: positionPoints += points
        case .finish: finishPoints += points
        case .collision: collisionPoints += points
        }
    }

    func scoreBreakdownEntries() -> [ScoreBreakdownEntry] {
        ScoreSource.allCases.compactMap { source in
            let awardedPoints: Double
            switch source {
            case .distance: awardedPoints = distancePoints
            case .speed: awardedPoints = speedPoints
            case .boost: awardedPoints = boostPoints
            case .overtake: awardedPoints = overtakePoints
            case .nearMiss: awardedPoints = nearMissPoints
            case .drift: awardedPoints = driftPoints
            case .checkpoint: awardedPoints = checkpointPoints
            case .position: awardedPoints = positionPoints
            case .finish: awardedPoints = finishPoints
            case .collision: awardedPoints = collisionPoints
            }
            guard awardedPoints != 0 else { return nil }
            return ScoreBreakdownEntry(
                source: source,
                eventCount: 0,
                basePoints: awardedPoints,
                awardedPoints: awardedPoints
            )
        }
    }
}

extension RaceSimulation {
    mutating func ingest(_ event: GameplayScoreEvent) {
        guard state.phase == .racing || state.phase == .fork || state.phase == .checkpoint else {
            return
        }

        switch event {
        case .overtake(let id):
            guard acceptPass(id, source: .overtake, cooldown: 0.15) else { return }
            awardSkill(
                source: .overtake,
                basePoints: configuration.arcadeScoring.overtakePoints,
                boostEarned: 0.3
            )
        case .nearMiss(let id, let proximity):
            guard proximity.isFinite,
                  acceptPass(id, source: .nearMiss, cooldown: 0.25) else { return }
            let risk = (1 - proximity.clamped(to: 0...1))
            awardSkill(
                source: .nearMiss,
                basePoints: configuration.arcadeScoring.nearMissBasePoints
                    + configuration.arcadeScoring.nearMissRiskPoints * risk,
                boostEarned: 0.25 + 0.35 * risk
            )
        case .drift(let id, let duration, let intensity):
            guard duration.isFinite, intensity.isFinite,
                  acceptUnique(id, source: .drift, cooldown: 0.5) else { return }
            let cappedDuration = duration.clamped(to: 0...3)
            let cappedIntensity = intensity.clamped(to: 0...1)
            guard cappedDuration >= 0.25, cappedIntensity >= 0.2 else { return }
            awardSkill(
                source: .drift,
                basePoints: configuration.arcadeScoring.driftPointsPerSecond
                    * cappedDuration * cappedIntensity,
                boostEarned: min(0.75, 0.18 * cappedDuration * cappedIntensity)
            )
        case .checkpoint(let id, let secondsUnderPar):
            guard secondsUnderPar.isFinite,
                  acceptUnique(id, source: .checkpoint, cooldown: 0) else { return }
            awardSkill(
                source: .checkpoint,
                basePoints: configuration.arcadeScoring.checkpointPoints
                    + configuration.arcadeScoring.checkpointPointsPerSecond
                        * secondsUnderPar.clamped(to: 0...8),
                boostEarned: 0
            )
        case .position(let place):
            guard place > 0 else { return }
            if let lastAwardedPosition, place >= lastAwardedPosition {
                return
            }
            lastAwardedPosition = place
            award(
                source: .position,
                basePoints: Double(max(0, 7 - place))
                    * configuration.arcadeScoring.positionPointsPerPlace
            )
        case .collision(let id, let severity):
            handleCollision(id: id, severity: severity)
        case .finish(let position):
            guard !didAwardFinish else { return }
            didAwardFinish = true
            let placementBonus = position.map {
                Double(max(0, 7 - $0))
                    * configuration.arcadeScoring.finishPositionPointsPerPlace
            } ?? 0
            award(
                source: .finish,
                basePoints: configuration.arcadeScoring.finishPoints + placementBonus
            )
        }
    }

    var scoreResult: ScoreResult {
        let entries = ScoreSource.allCases.compactMap { source -> ScoreBreakdownEntry? in
            let matching = scoreEvents.filter { $0.source == source }
            guard !matching.isEmpty else { return nil }
            return ScoreBreakdownEntry(
                source: source,
                eventCount: matching.count,
                basePoints: matching.reduce(0) { $0 + $1.basePoints },
                awardedPoints: matching.reduce(0) { $0 + $1.points }
            )
        }
        return ScoreResult(score: state.score, rank: currentRank, breakdown: entries)
    }
}

extension Comparable {
    fileprivate func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
