import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct RaceScoringTests {
    @Test
    func typedEventsProduceDeterministicTraceAndBreakdown() {
        var first = RaceSimulation(seed: 10, countdownDuration: 0)
        var second = RaceSimulation(seed: 10, countdownDuration: 0)

        for _ in 0..<120 {
            let command = PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false)
            first.advance(frameDelta: 1.0 / 120.0, command: command)
            second.advance(frameDelta: 1.0 / 120.0, command: command)
        }

        let inputs: [GameplayScoreEvent] = [
            .overtake(id: 1),
            .nearMiss(id: 2, proximity: 0.1),
            .drift(id: 3, duration: 1.5, intensity: 0.8),
            .checkpoint(id: 4, secondsUnderPar: 2),
            .position(place: 2),
            .finish(position: 2)
        ]
        for input in inputs {
            first.ingest(input)
            second.ingest(input)
        }

        #expect(first.state == second.state)
        #expect(first.scoreEvents == second.scoreEvents)
        #expect(first.scoreResult == second.scoreResult)
        #expect(Set(first.scoreResult.breakdown.map(\.source)).isSuperset(
            of: [.distance, .overtake, .nearMiss, .drift, .checkpoint, .position, .finish]
        ))
        #expect(first.scoreEvents.enumerated().allSatisfy { $0.offset == $0.element.sequence })
        #expect(first.scoreEvents.last?.totalAfter == first.state.score)
        let tracedSources = Set(first.scoreEvents.map(\.source))
        let breakdownSources = Set(first.scoreResult.breakdown.map(\.source))
        #expect(breakdownSources == tracedSources)
        #expect(abs(first.scoreResult.breakdown.reduce(0) { $0 + $1.awardedPoints } - first.state.score) < 0.001)
    }

    @Test
    func replayReproducesExternalGameplayEventScoringAndBoostState() throws {
        let run = try RaceCommandRun(
            frameDelta: 1.0 / 120.0,
            repeatCount: 700,
            command: PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: true)
        )
        let recorded = [
            try RecordedGameplayScoreEvent(frameIndex: 370, event: .overtake(id: 10)),
            try RecordedGameplayScoreEvent(
                frameIndex: 371,
                event: .nearMiss(id: 11, proximity: 0.1)
            )
        ]
        let replay = RaceReplay(
            seed: 22,
            commandRuns: [run],
            gameplayEvents: recorded
        )

        let first = try RaceReplayExecutor.run(replay, verifyEvents: false)
        let second = try RaceReplayExecutor.run(replay, verifyEvents: false)

        #expect(first == second)
        #expect(first.scoreEvents.contains { $0.source == .overtake })
        #expect(first.scoreEvents.contains { $0.source == .nearMiss })
        #expect(first.scoreEvents.contains { $0.source == .boost })
        #expect(first.finalState.boostState == second.finalState.boostState)
        #expect(first.finalState.boostCharge == second.finalState.boostCharge)
    }

    @Test
    func comboGrowsDecaysAndBreaksOnCollision() {
        var simulation = runningSimulation()
        simulation.ingest(.overtake(id: 1))
        simulation.ingest(.nearMiss(id: 2, proximity: 0.2))

        #expect(simulation.state.combo.chainCount == 2)
        #expect(simulation.state.combo.multiplier == 1.25)

        advance(
            &simulation,
            seconds: 3.1,
            command: PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false)
        )
        #expect(simulation.state.combo.chainCount == 1)
        #expect(simulation.state.combo.multiplier == 1)

        simulation.ingest(.collision(id: 9, severity: 0.5))
        #expect(simulation.state.combo.chainCount == 0)
        #expect(simulation.state.combo.multiplier == 1)
    }

    @Test
    func duplicateAndRapidEventsCannotFarmScore() {
        var simulation = runningSimulation()
        simulation.ingest(.overtake(id: 100))
        let afterFirst = simulation.state.scoreInputs.overtakePoints

        simulation.ingest(.overtake(id: 100))
        simulation.ingest(.overtake(id: 101))
        simulation.ingest(.nearMiss(id: 100, proximity: 0))

        #expect(simulation.state.scoreInputs.overtakePoints == afterFirst)
        #expect(simulation.scoreEvents.filter { $0.source == .overtake }.count == 1)
        #expect(simulation.state.scoreInputs.nearMissPoints == 0)

        var nearMissFirst = runningSimulation()
        nearMissFirst.ingest(.nearMiss(id: 200, proximity: 0))
        nearMissFirst.ingest(.overtake(id: 200))
        #expect(nearMissFirst.scoreEvents.filter { $0.source == .nearMiss }.count == 1)
        #expect(nearMissFirst.scoreEvents.filter { $0.source == .overtake }.isEmpty)
        #expect(nearMissFirst.state.combo.chainCount == 1)
    }

    @Test
    func collisionPenaltyIsCappedAndAppliedOnlyOncePerCollision() {
        var simulation = runningSimulation()
        simulation.ingest(.collision(id: 7, severity: 100))
        simulation.ingest(.collision(id: 7, severity: 100))

        #expect(simulation.state.scoreInputs.collisionPoints == -400)
        #expect(simulation.scoreEvents.filter { $0.source == .collision }.count == 1)
    }

    @Test
    func riskyPlayEarnsBoostAndBoostMovesThroughExplicitStates() {
        var simulation = runningSimulation()
        let initial = simulation.state.boostCharge
        simulation.ingest(.nearMiss(id: 1, proximity: 0))
        #expect(simulation.state.boostCharge > initial)

        let boost = PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: true)
        simulation.advance(frameDelta: 1.0 / 120.0, command: boost)
        #expect(simulation.state.boostState == .starting)
        simulation.advance(frameDelta: 1.0 / 120.0, command: boost)
        #expect(simulation.state.boostState == .active)

        simulation.advance(
            frameDelta: 1.0 / 120.0,
            command: PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false)
        )
        #expect(simulation.state.boostState == .ending)
        simulation.advance(
            frameDelta: 1.0 / 120.0,
            command: PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false)
        )
        #expect(simulation.state.boostState == .unavailable)
        #expect(simulation.state.boostCharge < RaceConfiguration.standard.boost.capacity)
    }

    @Test
    func rankThresholdsApplyToResultBreakdown() {
        let scoring = RaceConfiguration.standard.scoring
        #expect(scoring.rank(for: scoring.bronzeThreshold - 0.01) == .unranked)
        #expect(scoring.rank(for: scoring.bronzeThreshold) == .bronze)
        #expect(scoring.rank(for: scoring.silverThreshold) == .silver)
        #expect(scoring.rank(for: scoring.goldThreshold) == .gold)
    }

    @Test
    func completingRouteAwardsCheckpointAndFinishWithoutManualIngestion() {
        let route = RouteGraph(
            startStageID: "opening",
            stages: [
                RouteStage(
                    id: "opening",
                    displayName: "Opening",
                    environmentID: "coast",
                    distance: 0.001,
                    checkpointTimeAward: 5,
                    branches: [
                        RouteBranch(
                            id: "continue",
                            direction: .straight,
                            destinationStageID: "finish",
                            previewName: "Finish"
                        )
                    ]
                ),
                RouteStage(
                    id: "finish",
                    displayName: "Finish",
                    environmentID: "city",
                    distance: 0.001,
                    checkpointTimeAward: 0,
                    branches: []
                )
            ],
            forkDecisionDistance: 0,
            minimumForkDecisionTime: 0
        )
        var simulation = RaceSimulation(
            seed: 14,
            routeGraph: route,
            countdownDuration: 0
        )
        let command = PlayerCommand(
            steering: 0,
            throttle: 1,
            brake: 0,
            isBoosting: false
        )

        for _ in 0..<10 where simulation.state.phase != .finished {
            simulation.advance(frameDelta: 1.0 / 120.0, command: command)
        }

        #expect(simulation.state.phase == .finished)
        #expect(simulation.scoreResult.breakdown.contains { $0.source == .checkpoint })
        #expect(simulation.scoreResult.breakdown.contains { $0.source == .finish })
        #expect(simulation.scoreEvents.last?.totalAfter == simulation.state.score)
    }

    private func runningSimulation() -> RaceSimulation {
        var simulation = RaceSimulation(seed: 1, countdownDuration: 0)
        simulation.advance(frameDelta: 1.0 / 120.0, command: .idle)
        return simulation
    }

    private func advance(
        _ simulation: inout RaceSimulation,
        seconds: TimeInterval,
        command: PlayerCommand
    ) {
        for _ in 0..<Int(seconds * 120) {
            simulation.advance(frameDelta: 1.0 / 120.0, command: command)
        }
    }
}
