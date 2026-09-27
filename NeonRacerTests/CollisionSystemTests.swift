import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct CollisionSystemTests {
    @Test
    func trafficCollisionSlowsPlayerAndStartsSingleRecoveryWindow() {
        var state = runningState()
        state.speed = 100
        state.traffic = [TrafficVehicleState(
            id: 42,
            kind: .commuter,
            distance: state.distance,
            lateralPosition: state.lateralPosition,
            speed: 58,
            halfWidth: 0.18
        )]
        var system = CollisionSystem()

        let first = system.update(
            state: &state,
            configuration: .standard,
            trackLayout: .initialContent(),
            deltaTime: 1.0 / 120.0
        )
        let speedAfterCollision = state.speed
        let timerAfterCollision = state.timerRemaining
        let second = system.update(
            state: &state,
            configuration: .standard,
            trackLayout: .initialContent(),
            deltaTime: 1.0 / 120.0
        )

        #expect(first.scoringSignals.count == 1)
        #expect(first.scoringSignals.first?.cues.contains(.crash) == true)
        #expect(speedAfterCollision < 65)
        #expect(state.vehicle.crashRecoveryRemaining > 1.0)
        #expect(timerAfterCollision == 87)
        #expect(state.lastTimePenalty == 3)
        #expect(state.lastTimePenaltyTime == 12)
        #expect(second.scoringSignals.isEmpty)
        #expect(state.timerRemaining == timerAfterCollision)
    }

    @Test
    func obstacleCollisionMarksHitAndAppliesLargerSlowdown() {
        var state = runningState()
        state.speed = 100
        state.obstacles = [TrackObstacleState(
            id: 77,
            kind: .neonBarrier,
            distance: state.distance,
            lateralPosition: state.lateralPosition,
            halfWidth: 0.2
        )]
        var system = CollisionSystem()

        let result = system.update(
            state: &state,
            configuration: .standard,
            trackLayout: .initialContent(),
            deltaTime: 1.0 / 120.0
        )

        #expect(result.scoringSignals.count == 1)
        #expect(result.scoringSignals.first?.cues.contains(.obstacleHit) == true)
        #expect(result.scoringSignals.first?.timePenalty == 2)
        #expect(state.speed < 50)
        #expect(state.timerRemaining == 88)
        #expect(state.obstacles.first?.isHit == true)
        #expect(state.vehicle.crashRecoveryRemaining >= 1.2)
    }

    @Test
    func roadsideHazardsApplyRoadsidePenaltyAndTimerNeverGoesNegative() {
        var state = runningState()
        state.timerRemaining = 1
        state.speed = 100
        state.lateralPosition = 1.24
        state.obstacles = [TrackObstacleState(
            id: 88,
            kind: .holoSignPylon,
            distance: state.distance,
            lateralPosition: 1.24,
            halfWidth: 0.12
        )]
        var system = CollisionSystem()

        let result = system.update(
            state: &state,
            configuration: .standard,
            trackLayout: .initialContent(),
            deltaTime: 1.0 / 120.0
        )

        #expect(result.scoringSignals.first?.timePenalty == 1)
        #expect(state.timerRemaining == 0)
        #expect(state.lastTimePenalty == 1)
    }

    @Test
    func nearMissAndOvertakeAreEmittedOncePerVehicle() {
        var state = runningState()
        state.speed = 96
        state.lateralPosition = -0.15
        state.traffic = [TrafficVehicleState(
            id: 9,
            kind: .commuter,
            distance: state.distance - 3,
            lateralPosition: 0.15,
            speed: 70,
            halfWidth: 0.02
        )]
        var system = CollisionSystem()

        let first = system.update(
            state: &state,
            configuration: .standard,
            trackLayout: .initialContent(),
            deltaTime: 1.0 / 120.0
        )
        let second = system.update(
            state: &state,
            configuration: .standard,
            trackLayout: .initialContent(),
            deltaTime: 1.0 / 120.0
        )
        let events = first.scoringSignals.map(\.event)

        #expect(events.contains { if case .nearMiss = $0 { true } else { false } })
        #expect(events.contains { if case .overtake(id: 9) = $0 { true } else { false } })
        #expect(state.traffic.first?.hasBeenPassed == true)
        #expect(second.scoringSignals.isEmpty)
    }

    @Test
    func raceSimulationProcessesCollisionScoreOnlyOncePerID() {
        var simulation = RaceSimulation(seed: 5, countdownDuration: 0)
        simulation.advance(frameDelta: 1.0 / 120.0, command: .idle)

        simulation.ingest(.collision(id: 123, severity: 1))
        simulation.ingest(.collision(id: 123, severity: 1))

        #expect(simulation.scoreEvents.filter { $0.source == .collision }.count == 1)
        #expect(simulation.state.vehicle.crashRecoveryRemaining == 0)
    }

    @Test
    func timePenaltyEventsMapToCrashHudFeedback() {
        let eventFeedback = HUDCalloutMapper.feedback(
            for: RunEvent.timePenalty(time: 12, seconds: 3),
            checkpointNumber: 0
        )
        var state = runningState()
        state.lastTimePenalty = 2
        let cueFeedback = HUDCalloutMapper.feedback(
            for: RaceFeedbackCue.timePenalty,
            state: state,
            configuration: .standard
        )

        #expect(eventFeedback == .crashTimePenalty(seconds: 3))
        #expect(cueFeedback == .crashTimePenalty(seconds: 2))
    }

    private func runningState() -> RaceState {
        var state = RaceState(
            elapsedTime: 12,
            vehicle: VehicleState(),
            timerRemaining: 90,
            boostCharge: 0,
            stageProgress: 0.4,
            trafficDensity: 0.5,
            phase: .racing,
            countdownRemaining: 0,
            currentStageID: "coast-causeway",
            currentStageDistance: 360,
            currentEnvironmentID: "sunset-coast"
        )
        state.distance = 360
        state.lateralPosition = 0
        return state
    }
}
