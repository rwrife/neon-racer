#if DEBUG
import Foundation

struct RaceDevelopmentSpeedDistribution: Equatable, Sendable {
    var minimum: Double = 0
    var average: Double = 0
    var maximum: Double = 0
}

struct RaceDevelopmentRunSummary: Equatable, Sendable {
    var failureCount: Int = 0
    var trafficCollisionCount: Int = 0
    var obstacleCollisionCount: Int = 0
    var missedForkCount: Int = 0
    var checkpointMargins: [TimeInterval] = []
    var speedDistribution = RaceDevelopmentSpeedDistribution()
    var boostActivationCount: Int = 0
    var boostActiveTime: TimeInterval = 0
    var scoreBySource: [ScoreSource: Double] = [:]
}

struct RaceDevelopmentRunInstrumentation: Equatable, Sendable {
    private var speedSampleCount = 0
    private var speedSum = 0.0
    private var minimumSpeed = Double.infinity
    private var maximumSpeed = 0.0
    var boostActivationCount = 0
    var boostActiveTime: TimeInterval = 0
    var trafficCollisionCount = 0
    var obstacleCollisionCount = 0
    var missedForkCount = 0
    var checkpointMargins: [TimeInterval] = []

    mutating func recordFrame(state: RaceState, deltaTime: TimeInterval) {
        guard state.phase == .racing || state.phase == .fork || state.phase == .checkpoint else {
            return
        }
        speedSampleCount += 1
        speedSum += state.speed
        minimumSpeed = min(minimumSpeed, state.speed)
        maximumSpeed = max(maximumSpeed, state.speed)
        if state.isBoostActive {
            boostActiveTime += deltaTime
        }
    }

    mutating func recordBoostActivation() {
        boostActivationCount += 1
    }

    mutating func recordCollision(cues: [RaceFeedbackCue]) {
        if cues.contains(.obstacleHit) {
            obstacleCollisionCount += 1
        } else {
            trafficCollisionCount += 1
        }
    }

    mutating func recordMissedFork() {
        missedForkCount += 1
    }

    mutating func recordCheckpointMargin(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        checkpointMargins.append(seconds)
    }

    func summary(runEvents: [RunEvent], scoreEvents: [ScoreEvent]) -> RaceDevelopmentRunSummary {
        let speedDistribution: RaceDevelopmentSpeedDistribution
        if speedSampleCount > 0 {
            speedDistribution = RaceDevelopmentSpeedDistribution(
                minimum: minimumSpeed,
                average: speedSum / Double(speedSampleCount),
                maximum: maximumSpeed
            )
        } else {
            speedDistribution = RaceDevelopmentSpeedDistribution()
        }
        let scoreBySource = Dictionary(
            grouping: scoreEvents,
            by: \.source
        ).mapValues { events in
            events.reduce(0) { $0 + $1.points }
        }
        return RaceDevelopmentRunSummary(
            failureCount: runEvents.filter { event in
                if case .failed = event { return true }
                return false
            }.count,
            trafficCollisionCount: trafficCollisionCount,
            obstacleCollisionCount: obstacleCollisionCount,
            missedForkCount: missedForkCount,
            checkpointMargins: checkpointMargins,
            speedDistribution: speedDistribution,
            boostActivationCount: boostActivationCount,
            boostActiveTime: boostActiveTime,
            scoreBySource: scoreBySource
        )
    }
}

struct RaceReplayDiagnosticSnapshot: Equatable, Sendable {
    let seed: UInt64
    let frameCount: Int
    let commandRunCount: Int
    let finalState: RaceState
    let events: [RaceEvent]
}

protocol RaceReplayDiagnosticSink: Sendable {
    func receive(_ snapshot: RaceReplayDiagnosticSnapshot)
}

struct DisabledRaceReplayDiagnosticSink: RaceReplayDiagnosticSink {
    func receive(_ snapshot: RaceReplayDiagnosticSnapshot) {}
}

extension RaceReplayResult {
    func diagnosticSnapshot(for replay: RaceReplay) -> RaceReplayDiagnosticSnapshot {
        RaceReplayDiagnosticSnapshot(
            seed: replay.seed,
            frameCount: frameCount,
            commandRunCount: replay.commandRuns.count,
            finalState: finalState,
            events: events
        )
    }
}
#endif
