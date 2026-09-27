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

    mutating func reset() {
        progress = .notStarted
    }
}

