import Foundation

enum HUDCalloutMapper {
    static let defaultCrashTimePenaltySeconds = 3

    static func countdownSecond(phase: RacePhase, countdownRemaining: TimeInterval) -> Int? {
        phase == .countdown && countdownRemaining > 0
            ? Int(countdownRemaining.rounded(.up))
            : nil
    }

    static func feedback(
        for scoreEvent: ScoreEvent,
        comboMultiplier: Double?
    ) -> RaceHUDFeedback? {
        let points = Int(scoreEvent.points.rounded())
        switch scoreEvent.source {
        case .distance, .speed, .boost:
            return nil
        case .nearMiss:
            return .nearMiss(points: points)
        case .overtake:
            return .overtake(points: points)
        case .drift:
            return .drift(multiplier: comboMultiplier ?? scoreEvent.multiplier, points: points)
        case .checkpoint:
            return .score(source: .checkpoint, points: points)
        case .position:
            return .score(source: .position, points: points)
        case .finish:
            return .finished
        case .collision:
            return .collision
        }
    }

    static func feedback(
        for cue: RaceFeedbackCue,
        state: RaceState,
        configuration: RaceConfiguration
    ) -> RaceHUDFeedback? {
        switch cue {
        case .comboIncreased:
            return .comboIncreased(state.combo.multiplier)
        case .comboBroken:
            return .comboBroken
        case .collisionPenalty:
            return .collision
        case .timePenalty:
            return .crashTimePenalty(seconds: max(0, Int(state.lastTimePenalty.rounded())))
        case .rankChanged:
            return .rankChanged(configuration.scoring.rank(for: state.score))
        case .boostStarting, .boostActive:
            return .boostEngaged
        case .scoreAwarded, .comboDecayed, .boostEarned, .boostEnding, .boostUnavailable:
            return feedback(forRawCue: cue.rawValue)
        default:
            return feedback(forRawCue: cue.rawValue)
        }
    }

    static func feedback(for event: RunEvent, checkpointNumber: Int) -> RaceHUDFeedback? {
        switch event {
        case .raceStarted:
            return .go
        case .forkPresented(_, _, let branches):
            let left = branches.first { $0.direction == .left }?.previewName
            let right = branches.first { $0.direction == .right }?.previewName
            return .forkPreview(left: left, right: right)
        case .branchCommitted(_, _, let branch):
            return .routeChosen(branch.previewName)
        case .checkpointCrossed(_, _, _, let timeAward):
            let seconds = max(0, Int(timeAward.rounded()))
            return .checkpointBonus(number: checkpointNumber, seconds: seconds)
        case .stageChanged(_, let stageID, _):
            return stageID.localizedCaseInsensitiveContains("final") ? .finalStretch : nil
        case .timePenalty(_, let seconds):
            return .crashTimePenalty(seconds: max(0, Int(seconds.rounded())))
        case .finished:
            return .finished
        case .failed:
            return .failed
        default:
            return nil
        }
    }

    static func feedback(
        forRawCue rawValue: String,
        defaultTimePenaltySeconds: Int = defaultCrashTimePenaltySeconds
    ) -> RaceHUDFeedback? {
        switch rawValue.replacingOccurrences(of: "_", with: "").lowercased() {
        case "nearmiss":
            return .nearMiss(points: 0)
        case "overtake":
            return .overtake(points: 0)
        case "crash", "obstaclehit", "timepenalty", "crashtimepenalty":
            return .crashTimePenalty(seconds: defaultTimePenaltySeconds)
        default:
            return nil
        }
    }
}
