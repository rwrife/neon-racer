import Foundation

enum RaceHUDWarning: Equatable, Sendable {
    case timeCritical
    case roadEdge
    case boostDepleted
}

enum RaceHUDFeedback: Equatable, Sendable {
    case countdown(Int)
    case go
    case boostEngaged
    case checkpoint(number: Int)
    case routeFork
    case routeChosen(String)
    case score(source: ScoreSource, points: Int)
    case comboIncreased(Double)
    case comboBroken
    case collision
    case finished
    case failed
}

struct RaceHUDSnapshot: Equatable, Sendable {
    let speedMPH: Int
    let score: Int
    let timerSeconds: Int
    let countdownSeconds: Int?
    let stageNumber: Int
    let stageProgress: Double
    let routeName: String?
    let comboMultiplier: Double?
    let boostFraction: Double
    let isBoostActive: Bool
    let phase: RacePhase
    let warning: RaceHUDWarning?

    static let initial = RaceHUDSnapshot(
        state: RaceState(),
        configuration: .standard
    )

    private init(
        speedMPH: Int,
        score: Int,
        timerSeconds: Int,
        countdownSeconds: Int?,
        stageNumber: Int,
        stageProgress: Double,
        routeName: String?,
        comboMultiplier: Double?,
        boostFraction: Double,
        isBoostActive: Bool,
        phase: RacePhase,
        warning: RaceHUDWarning?
    ) {
        self.speedMPH = speedMPH
        self.score = score
        self.timerSeconds = timerSeconds
        self.countdownSeconds = countdownSeconds
        self.stageNumber = stageNumber
        self.stageProgress = stageProgress
        self.routeName = routeName
        self.comboMultiplier = comboMultiplier
        self.boostFraction = boostFraction
        self.isBoostActive = isBoostActive
        self.phase = phase
        self.warning = warning
    }

    init(state: RaceState, configuration: RaceConfiguration) {
        speedMPH = max(0, Int((state.speed * 2.236_936).rounded()))
        score = max(0, Int(state.score.rounded(.down)))
        timerSeconds = max(0, Int(state.timerRemaining.rounded(.up)))
        countdownSeconds = state.phase == .countdown && state.countdownRemaining > 0
            ? Int(state.countdownRemaining.rounded(.up))
            : nil
        stageNumber = state.completedStageIDs.count + 1
        stageProgress = state.stageProgress.clamped(to: 0...1)
        routeName = state.committedBranchIDs.last.map {
            $0.replacingOccurrences(of: "-", with: " ").uppercased()
        } ?? (state.currentStageID.isEmpty
            ? nil
            : state.currentStageID.replacingOccurrences(of: "-", with: " ").uppercased())
        comboMultiplier = state.combo.chainCount > 0 ? state.combo.multiplier : nil
        boostFraction = (state.boostCharge / configuration.boost.capacity).clamped(to: 0...1)
        isBoostActive = state.isBoostActive
        phase = state.phase

        if state.phase == .racing, state.timerRemaining <= 10 {
            warning = .timeCritical
        } else if abs(state.lateralPosition) >= 0.9 {
            warning = .roadEdge
        } else if state.phase == .racing, state.boostCharge <= 0.05 {
            warning = .boostDepleted
        } else {
            warning = nil
        }
    }
}

struct RaceHUDUpdate: Equatable, Sendable {
    let snapshot: RaceHUDSnapshot
    let feedback: RaceHUDFeedback?
}

struct RaceHUDTracker: Sendable {
    private(set) var consumedEventCount = 0
    private(set) var consumedScoreEventCount = 0
    private(set) var consumedFeedbackEventCount = 0
    private(set) var consumedRunEventCount = 0
    private(set) var checkpointNumber = 0
    private var lastCountdownSecond: Int?

    mutating func update(
        state: RaceState,
        events: [RaceEvent],
        scoreEvents: [ScoreEvent] = [],
        feedbackEvents: [RaceFeedbackEvent] = [],
        runEvents: [RunEvent] = [],
        configuration: RaceConfiguration
    ) -> RaceHUDUpdate {
        var feedback: RaceHUDFeedback?

        if consumedEventCount > events.count {
            consumedEventCount = 0
            checkpointNumber = 0
        }
        if consumedScoreEventCount > scoreEvents.count {
            consumedScoreEventCount = 0
        }
        if consumedFeedbackEventCount > feedbackEvents.count {
            consumedFeedbackEventCount = 0
        }
        if consumedRunEventCount > runEvents.count {
            consumedRunEventCount = 0
            checkpointNumber = 0
        }

        for event in events.dropFirst(consumedEventCount) {
            switch event {
            case .started:
                feedback = .go
            case .boostStarted:
                feedback = .boostEngaged
            case .boostEnded:
                break
            case .finished:
                feedback = .finished
            case .failed:
                feedback = .failed
            }
        }
        consumedEventCount = events.count

        if let skillScore = scoreEvents.dropFirst(consumedScoreEventCount).last(where: {
            ![.distance, .speed, .boost].contains($0.source)
        }) {
            feedback = .score(
                source: skillScore.source,
                points: Int(skillScore.points.rounded())
            )
        }
        consumedScoreEventCount = scoreEvents.count

        for event in feedbackEvents.dropFirst(consumedFeedbackEventCount)
            where event.channels.contains(.hud) {
            switch event.cue {
            case .comboIncreased:
                feedback = .comboIncreased(state.combo.multiplier)
            case .comboBroken:
                feedback = .comboBroken
            case .collisionPenalty:
                feedback = .collision
            default:
                break
            }
        }
        consumedFeedbackEventCount = feedbackEvents.count

        for event in runEvents.dropFirst(consumedRunEventCount) {
            switch event {
            case .checkpointCrossed:
                checkpointNumber += 1
                feedback = .checkpoint(number: checkpointNumber)
            case .forkPresented:
                feedback = .routeFork
            case .branchCommitted(_, _, let branch):
                feedback = .routeChosen(branch.previewName)
            default:
                break
            }
        }
        consumedRunEventCount = runEvents.count

        let countdownSecond = state.phase == .countdown && state.countdownRemaining > 0
            ? Int(state.countdownRemaining.rounded(.up))
            : nil
        if let countdownSecond, countdownSecond != lastCountdownSecond {
            feedback = .countdown(countdownSecond)
        }
        lastCountdownSecond = countdownSecond

        return RaceHUDUpdate(
            snapshot: RaceHUDSnapshot(state: state, configuration: configuration),
            feedback: feedback
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
