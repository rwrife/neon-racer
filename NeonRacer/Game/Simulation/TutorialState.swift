import Foundation

enum TutorialStep: String, Codable, CaseIterable, Equatable, Sendable {
    case steering
    case brakingAndRecovery
    case boost
    case trafficRisk
    case checkpointTimer
    case routeFork

    var next: TutorialStep? {
        guard let index = Self.allCases.firstIndex(of: self) else { return nil }
        let nextIndex = Self.allCases.index(after: index)
        return nextIndex < Self.allCases.endIndex ? Self.allCases[nextIndex] : nil
    }
}

struct TutorialDrivingObservation: Equatable, Sendable {
    var command: PlayerCommand
    var phase: RacePhase
    var speedKPH: Int
    var isBoostActive: Bool
    var warning: RaceHUDWarning?
    var feedback: RaceHUDFeedback?
    var routeProgressMarkers: [HUDRouteProgressMarker]

    init(
        command: PlayerCommand = .idle,
        phase: RacePhase = .loading,
        speedKPH: Int = 0,
        isBoostActive: Bool = false,
        warning: RaceHUDWarning? = nil,
        feedback: RaceHUDFeedback? = nil,
        routeProgressMarkers: [HUDRouteProgressMarker] = []
    ) {
        self.command = command
        self.phase = phase
        self.speedKPH = speedKPH
        self.isBoostActive = isBoostActive
        self.warning = warning
        self.feedback = feedback
        self.routeProgressMarkers = routeProgressMarkers
    }

    init(snapshot: RaceHUDSnapshot, command: PlayerCommand, feedback: RaceHUDFeedback?) {
        self.init(
            command: command,
            phase: snapshot.phase,
            speedKPH: snapshot.speedKPH,
            isBoostActive: snapshot.isBoostActive,
            warning: snapshot.warning,
            feedback: feedback,
            routeProgressMarkers: snapshot.routeProgressMarkers
        )
    }
}

enum TutorialStatus: String, Codable, Equatable, Sendable {
    case notStarted
    case inProgress
    case completed
    case skipped
}

struct TutorialProgress: Codable, Equatable, Sendable {
    var status: TutorialStatus
    var currentStep: TutorialStep?

    static let notStarted = TutorialProgress(status: .notStarted, currentStep: nil)
    static let completed = TutorialProgress(status: .completed, currentStep: nil)
}

struct TutorialSession: Equatable, Sendable {
    private(set) var progress: TutorialProgress

    init(progress: TutorialProgress = .notStarted) {
        self.progress = progress
    }

    var currentStep: TutorialStep? {
        progress.currentStep
    }

    var isPresenting: Bool {
        progress.status == .inProgress && currentStep != nil
    }

    mutating func startIfNeeded() {
        guard progress.status == .notStarted else { return }
        progress = TutorialProgress(status: .inProgress, currentStep: TutorialStep.allCases.first)
    }

    mutating func replay() {
        progress = .notStarted
        startIfNeeded()
    }

    mutating func advance() {
        guard progress.status == .inProgress, let currentStep else { return }

        if let nextStep = currentStep.next {
            progress.currentStep = nextStep
        } else {
            progress = .completed
        }
    }

    mutating func skip() {
        guard progress.status == .notStarted || progress.status == .inProgress else { return }
        progress = TutorialProgress(status: .skipped, currentStep: nil)
    }

    @discardableResult
    mutating func observe(_ observation: TutorialDrivingObservation) -> Bool {
        guard progress.status == .inProgress,
              let currentStep,
              currentStep.isSatisfied(by: observation) else {
            return false
        }

        advance()
        return true
    }

    mutating func reset() {
        progress = .notStarted
    }
}

extension TutorialStep {
    func isSatisfied(by observation: TutorialDrivingObservation) -> Bool {
        switch self {
        case .steering:
            observation.isRaceActive && abs(observation.command.steering) >= 0.35
        case .brakingAndRecovery:
            observation.isRaceActive
                && (
                    observation.command.throttle >= 0.5
                    || (observation.command.brake >= 0.5
                        && (observation.speedKPH >= 20 || observation.warning == .roadEdge))
                )
        case .boost:
            observation.isRaceActive
                && (observation.isBoostActive || observation.feedback == .boostEngaged)
        case .trafficRisk:
            observation.feedback.isDriftOrNearMiss
        case .checkpointTimer:
            observation.feedback.isCheckpoint
                || observation.routeProgressMarkers.contains {
                    $0.kind == .checkpoint && $0.isReached
                }
        case .routeFork:
            observation.feedback.isRouteChoice
        }
    }
}

private extension TutorialDrivingObservation {
    var isRaceActive: Bool {
        phase == .racing || phase == .fork || phase == .checkpoint
    }
}

private extension Optional where Wrapped == RaceHUDFeedback {
    var isDriftOrNearMiss: Bool {
        switch self {
        case .nearMiss, .drift:
            true
        default:
            false
        }
    }

    var isCheckpoint: Bool {
        switch self {
        case .checkpoint, .checkpointBonus, .score(source: .checkpoint, points: _):
            true
        default:
            false
        }
    }

    var isRouteChoice: Bool {
        switch self {
        case .routeChosen:
            true
        default:
            false
        }
    }
}
