enum RunInterruptionReason: String, CaseIterable, Equatable, Sendable {
    case appInactive
    case appBackground
    case audioInterruption
}

enum RunLifecycleState: Equatable, Sendable {
    case running
    case suspended(Set<RunInterruptionReason>)
    case pausedForRecovery
}

enum RunLifecycleEvent: Equatable, Sendable {
    case sceneBecameInactive
    case sceneEnteredBackground
    case sceneBecameActive
    case audioInterruptionBegan
    case audioInterruptionEnded
    case audioRouteChanged
    case controllerDisconnected
    case memoryWarningReceived
    case pauseRequested
    case resumeRequested
}

enum RunLifecycleAction: Equatable, Sendable {
    case pauseGameplay
    case stopFeedback
    case startFeedback
    case resumeGameplay
    case releaseRecreatableResources
}

struct RunInterruptionCoordinator: Equatable, Sendable {
    private(set) var state: RunLifecycleState = .running
    private var interruptions: Set<RunInterruptionReason> = []
    private var recoveryRequired = false

    @discardableResult
    mutating func handle(_ event: RunLifecycleEvent) -> [RunLifecycleAction] {
        switch event {
        case .sceneBecameInactive:
            return suspend(for: .appInactive)
        case .sceneEnteredBackground:
            return suspend(for: .appBackground)
        case .sceneBecameActive:
            interruptions.remove(.appInactive)
            interruptions.remove(.appBackground)
            return updateAfterRecovery()
        case .audioInterruptionBegan:
            return suspend(for: .audioInterruption)
        case .audioInterruptionEnded:
            interruptions.remove(.audioInterruption)
            return updateAfterRecovery()
        case .audioRouteChanged, .controllerDisconnected:
            return requireExplicitRecovery()
        case .memoryWarningReceived:
            return requireExplicitRecovery() + [.releaseRecreatableResources]
        case .pauseRequested:
            return requireExplicitRecovery()
        case .resumeRequested:
            guard interruptions.isEmpty, recoveryRequired else {
                return []
            }
            recoveryRequired = false
            state = .running
            return [.startFeedback, .resumeGameplay]
        }
    }

    private mutating func suspend(for reason: RunInterruptionReason) -> [RunLifecycleAction] {
        let wasRunning = !recoveryRequired
        interruptions.insert(reason)
        recoveryRequired = true
        state = .suspended(interruptions)
        return wasRunning ? [.pauseGameplay, .stopFeedback] : []
    }

    private mutating func requireExplicitRecovery() -> [RunLifecycleAction] {
        guard !recoveryRequired else {
            state = interruptions.isEmpty ? .pausedForRecovery : .suspended(interruptions)
            return []
        }
        recoveryRequired = true
        state = interruptions.isEmpty ? .pausedForRecovery : .suspended(interruptions)
        return [.pauseGameplay, .stopFeedback]
    }

    private mutating func updateAfterRecovery() -> [RunLifecycleAction] {
        if interruptions.isEmpty {
            state = recoveryRequired ? .pausedForRecovery : .running
        } else {
            state = .suspended(interruptions)
        }
        return []
    }
}
