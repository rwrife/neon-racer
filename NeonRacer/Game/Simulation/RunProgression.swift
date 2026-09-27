import Foundation

enum RacePhase: String, Codable, Equatable, Sendable {
    case loading
    case countdown
    case racing
    case checkpoint
    case fork
    case finished
    case failed
    case paused
    case restarting
}

enum RunEvent: Codable, Equatable, Sendable {
    case loadingCompleted(time: TimeInterval)
    case countdownStarted(time: TimeInterval, duration: TimeInterval)
    case raceStarted(time: TimeInterval)
    case forkPresented(time: TimeInterval, stageID: String, branches: [RouteBranch])
    case branchCommitted(time: TimeInterval, stageID: String, branch: RouteBranch)
    case checkpointCrossed(
        time: TimeInterval,
        completedStageID: String,
        nextStageID: String,
        timeAward: TimeInterval
    )
    case stageChanged(time: TimeInterval, stageID: String, environmentID: String)
    case paused(time: TimeInterval)
    case resumed(time: TimeInterval)
    case timePenalty(time: TimeInterval, seconds: TimeInterval)
    case restartRequested(time: TimeInterval)
    case finished(time: TimeInterval, route: [String])
    case failed(time: TimeInterval, stageID: String)
}

enum RouteDirection: String, Codable, CaseIterable, Equatable, Sendable {
    case left
    case right
    case straight
}

struct RouteBranch: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let direction: RouteDirection
    let destinationStageID: String
    let previewName: String
}

struct RouteStage: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let environmentID: String
    let distance: Double
    let checkpointTimeAward: TimeInterval
    let branches: [RouteBranch]
}

enum RouteGraphValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingStartStage(String)
    case duplicateStageID(String)
    case invalidStageDistance(String)
    case invalidCheckpointAward(String)
    case duplicateBranchID(stageID: String, branchID: String)
    case missingDestination(stageID: String, destinationID: String)
    case forkDecisionDistanceTooShort(stageID: String, required: Double, actual: Double)
    case forkLongerThanStage(stageID: String)
    case unreachableStage(String)
    case cycleDetected(String)
    case noFinishStage

    var description: String {
        switch self {
        case .missingStartStage(let id): "Missing start stage '\(id)'"
        case .duplicateStageID(let id): "Duplicate stage id '\(id)'"
        case .invalidStageDistance(let id): "Stage '\(id)' must have a finite, positive distance"
        case .invalidCheckpointAward(let id): "Stage '\(id)' must have a finite, nonnegative checkpoint award"
        case .duplicateBranchID(let stageID, let branchID):
            "Stage '\(stageID)' has duplicate branch id '\(branchID)'"
        case .missingDestination(let stageID, let destinationID):
            "Stage '\(stageID)' links to missing stage '\(destinationID)'"
        case .forkDecisionDistanceTooShort(let stageID, let required, let actual):
            "Stage '\(stageID)' fork needs \(required)m of warning, but has \(actual)m"
        case .forkLongerThanStage(let stageID):
            "Stage '\(stageID)' is shorter than its fork decision zone"
        case .unreachableStage(let id): "Stage '\(id)' is unreachable"
        case .cycleDetected(let id): "Route cycle detected at stage '\(id)'"
        case .noFinishStage: "Route graph has no finish stage"
        }
    }
}

struct RouteGraph: Codable, Equatable, Sendable {
    let startStageID: String
    let stages: [RouteStage]
    let forkDecisionDistance: Double
    let minimumForkDecisionTime: TimeInterval

    func stage(id: String) -> RouteStage? {
        stages.first { $0.id == id }
    }

    func validationErrors(maximumVehicleSpeed: Double) -> [RouteGraphValidationError] {
        var errors: [RouteGraphValidationError] = []
        var stagesByID: [String: RouteStage] = [:]

        for stage in stages {
            if stagesByID.updateValue(stage, forKey: stage.id) != nil {
                errors.append(.duplicateStageID(stage.id))
            }
            if !stage.distance.isFinite || stage.distance <= 0 {
                errors.append(.invalidStageDistance(stage.id))
            }
            if !stage.checkpointTimeAward.isFinite || stage.checkpointTimeAward < 0 {
                errors.append(.invalidCheckpointAward(stage.id))
            }
            var branchIDs: Set<String> = []
            for branch in stage.branches where !branchIDs.insert(branch.id).inserted {
                errors.append(.duplicateBranchID(stageID: stage.id, branchID: branch.id))
            }
        }

        guard stagesByID[startStageID] != nil else {
            errors.append(.missingStartStage(startStageID))
            return errors
        }

        let requiredDecisionDistance = maximumVehicleSpeed * minimumForkDecisionTime
        for stage in stages {
            for branch in stage.branches where stagesByID[branch.destinationStageID] == nil {
                errors.append(
                    .missingDestination(
                        stageID: stage.id,
                        destinationID: branch.destinationStageID
                    )
                )
            }
            if stage.branches.count > 1 {
                if forkDecisionDistance < requiredDecisionDistance {
                    errors.append(
                        .forkDecisionDistanceTooShort(
                            stageID: stage.id,
                            required: requiredDecisionDistance,
                            actual: forkDecisionDistance
                        )
                    )
                }
                if stage.distance < forkDecisionDistance {
                    errors.append(.forkLongerThanStage(stageID: stage.id))
                }
            }
        }

        if !stages.contains(where: \.branches.isEmpty) {
            errors.append(.noFinishStage)
        }

        var visited: Set<String> = []
        var active: Set<String> = []
        func visit(_ id: String) {
            guard let stage = stagesByID[id], !visited.contains(id) else { return }
            if active.contains(id) {
                errors.append(.cycleDetected(id))
                return
            }
            active.insert(id)
            for branch in stage.branches {
                visit(branch.destinationStageID)
            }
            active.remove(id)
            visited.insert(id)
        }
        visit(startStageID)
        for stage in stages where !visited.contains(stage.id) {
            errors.append(.unreachableStage(stage.id))
        }
        return errors
    }

    static func neonForkFixture(totalDistance: Double) -> RouteGraph {
        let openingDistance = totalDistance * 0.36
        let branchDistance = totalDistance * 0.29
        let finalDistance = totalDistance - openingDistance - branchDistance
        return RouteGraph(
            startStageID: "neon-causeway",
            stages: [
                RouteStage(
                    id: "neon-causeway",
                    displayName: "Neon Causeway",
                    environmentID: "neon-city",
                    distance: openingDistance,
                    checkpointTimeAward: 12,
                    branches: [
                        RouteBranch(
                            id: "harbor-left",
                            direction: .left,
                            destinationStageID: "harbor-sprint",
                            previewName: "Harbor / Fast"
                        ),
                        RouteBranch(
                            id: "skyway-right",
                            direction: .right,
                            destinationStageID: "skyway-climb",
                            previewName: "Skyway / Technical"
                        )
                    ]
                ),
                RouteStage(
                    id: "harbor-sprint",
                    displayName: "Harbor Sprint",
                    environmentID: "electric-harbor",
                    distance: branchDistance,
                    checkpointTimeAward: 10,
                    branches: [
                        RouteBranch(
                            id: "harbor-finale",
                            direction: .straight,
                            destinationStageID: "midnight-finale",
                            previewName: "Midnight Finale"
                        )
                    ]
                ),
                RouteStage(
                    id: "skyway-climb",
                    displayName: "Skyway Climb",
                    environmentID: "violet-skyway",
                    distance: branchDistance,
                    checkpointTimeAward: 14,
                    branches: [
                        RouteBranch(
                            id: "skyway-finale",
                            direction: .straight,
                            destinationStageID: "midnight-finale",
                            previewName: "Midnight Finale"
                        )
                    ]
                ),
                RouteStage(
                    id: "midnight-finale",
                    displayName: "Midnight Finale",
                    environmentID: "midnight-core",
                    distance: finalDistance,
                    checkpointTimeAward: 0,
                    branches: []
                )
            ],
            forkDecisionDistance: min(900, openingDistance),
            minimumForkDecisionTime: 5
        )
    }

    static func linearFixture(distance: Double) -> RouteGraph {
        RouteGraph(
            startStageID: "test-stage",
            stages: [
                RouteStage(
                    id: "test-stage",
                    displayName: "Test Stage",
                    environmentID: "test",
                    distance: distance,
                    checkpointTimeAward: 0,
                    branches: []
                )
            ],
            forkDecisionDistance: 0,
            minimumForkDecisionTime: 0
        )
    }
}
