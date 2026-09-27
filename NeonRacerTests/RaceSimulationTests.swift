import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct RaceSimulationTests {
    @Test
    func resultCapturesTypedScoreBreakdown() {
        var state = RaceState()
        state.phase = .finished
        state.elapsedTime = 42.5
        state.distance = 5_000
        state.scoreInputs.distancePoints = 5_000
        state.scoreInputs.boostPoints = 250

        let result = RaceResult(state: state, rank: .gold)

        #expect(result.outcome == .finished)
        #expect(result.score == 5_250)
        #expect(result.distancePoints == 5_000)
        #expect(result.boostPoints == 250)
        #expect(result.speedPoints == 0)
        #expect(result.rank == .gold)
        #expect(Set(result.scoreBreakdown.map(\.source)) == [.distance, .boost])
    }

    @Test
    func playerCommandsNormalizeAnalogRanges() {
        let command = PlayerCommand(
            steering: 4,
            throttle: -1,
            brake: 3,
            isBoosting: true
        )

        #expect(command.steering == 1)
        #expect(command.throttle == 0)
        #expect(command.brake == 1)
        #expect(command.isBoosting)
    }

    @Test
    func standardInputRemappingCoversEveryAction() {
        #expect(InputRemapping.standard.keyboard.keys.count == PlayerAction.allCases.count)
    }

    @Test
    func standardKeyboardSupportsWASDAndArrowDrivingAliases() {
        let mapping = InputRemapping.standard

        #expect(mapping.actions(for: .a).contains(.steerLeft))
        #expect(mapping.actions(for: .leftArrow).contains(.steerLeft))
        #expect(mapping.actions(for: .d).contains(.steerRight))
        #expect(mapping.actions(for: .rightArrow).contains(.steerRight))
        #expect(mapping.actions(for: .w).contains(.throttle))
        #expect(mapping.actions(for: .upArrow).contains(.throttle))
        #expect(mapping.actions(for: .s).contains(.brake))
        #expect(mapping.actions(for: .downArrow).contains(.brake))
        #expect(mapping.actions(for: .space).contains(.boost))
        #expect(mapping.actions(for: .escape).contains(.pause))
    }

    @Test
    func lifecycleRequiresExplicitResumeAfterReturningActive() {
        var lifecycle = RunInterruptionCoordinator()

        #expect(lifecycle.handle(.sceneBecameInactive) == [.pauseGameplay, .stopFeedback])
        #expect(lifecycle.state == .suspended([.appInactive]))
        #expect(lifecycle.handle(.sceneEnteredBackground).isEmpty)
        #expect(lifecycle.state == .suspended([.appInactive, .appBackground]))
        #expect(lifecycle.handle(.sceneBecameActive).isEmpty)
        #expect(lifecycle.state == .pausedForRecovery)
        #expect(lifecycle.handle(.resumeRequested) == [.startFeedback, .resumeGameplay])
        #expect(lifecycle.state == .running)
    }

    @Test
    func overlappingInterruptionsRecoverOnlyAfterEveryBlockerEnds() {
        var lifecycle = RunInterruptionCoordinator()

        #expect(lifecycle.handle(.sceneBecameInactive) == [.pauseGameplay, .stopFeedback])
        #expect(lifecycle.handle(.audioInterruptionBegan).isEmpty)
        #expect(lifecycle.handle(.sceneBecameActive).isEmpty)
        #expect(lifecycle.state == .suspended([.audioInterruption]))
        #expect(lifecycle.handle(.resumeRequested).isEmpty)
        #expect(lifecycle.handle(.audioInterruptionEnded).isEmpty)
        #expect(lifecycle.state == .pausedForRecovery)
    }

    @Test
    func repeatedLifecycleEventsDoNotDuplicateSideEffects() {
        var lifecycle = RunInterruptionCoordinator()

        #expect(lifecycle.handle(.audioInterruptionBegan) == [.pauseGameplay, .stopFeedback])
        #expect(lifecycle.handle(.audioInterruptionBegan).isEmpty)
        #expect(lifecycle.handle(.audioInterruptionEnded).isEmpty)
        #expect(lifecycle.handle(.audioInterruptionEnded).isEmpty)
        #expect(lifecycle.handle(.resumeRequested) == [.startFeedback, .resumeGameplay])
        #expect(lifecycle.handle(.resumeRequested).isEmpty)
    }

    @Test
    func manualPauseUsesTheSameDeterministicRecoveryPath() {
        var lifecycle = RunInterruptionCoordinator()

        #expect(lifecycle.handle(.pauseRequested) == [.pauseGameplay, .stopFeedback])
        #expect(lifecycle.state == .pausedForRecovery)
        #expect(lifecycle.handle(.pauseRequested).isEmpty)
        #expect(lifecycle.handle(.resumeRequested) == [.startFeedback, .resumeGameplay])
        #expect(lifecycle.state == .running)
    }

    @Test
    func identicalSeedsAndCommandsProduceIdenticalState() {
        var first = RaceSimulation(seed: 0xBEEF)
        var second = RaceSimulation(seed: 0xBEEF)

        let commands = scriptedCommands(totalDuration: 30)
        runSimulation(&first, commands: commands, frameRate: 60)
        runSimulation(&second, commands: commands, frameRate: 60)

        #expect(first.state == second.state)
    }

    @Test
    func renderRatesThirtySixtyAndOneTwentyRemainEquivalent() {
        let commands = scriptedCommands(totalDuration: 20)

        let configuration = RaceConfiguration.standard.withTrafficSpawningEnabled(false)
        var atThirty = RaceSimulation(configuration: configuration, seed: 42)
        var atSixty = RaceSimulation(configuration: configuration, seed: 42)
        var atOneTwenty = RaceSimulation(configuration: configuration, seed: 42)

        runSimulation(&atThirty, commands: commands, frameRate: 30)
        runSimulation(&atSixty, commands: commands, frameRate: 60)
        runSimulation(&atOneTwenty, commands: commands, frameRate: 120)

        assertStatesEquivalent(atThirty.state, atSixty.state)
        assertStatesEquivalent(atThirty.state, atOneTwenty.state)
    }

    @Test
    func pausePreventsTimeDistanceScoreTrafficAndStageProgress() {
        var simulation = RaceSimulation(seed: 7)
        let command = PlayerCommand(steering: 0.1, throttle: 1, brake: 0, isBoosting: true)

        simulation.advance(frameDelta: 1.0 / 60.0, command: command)
        let beforePause = simulation.state

        simulation.setPaused(true)
        for _ in 0..<240 {
            simulation.advance(frameDelta: 1.0 / 60.0, command: command)
        }
        let afterPause = simulation.state

        #expect(afterPause.phase == .paused)
        #expect(afterPause.elapsedTime == beforePause.elapsedTime)
        #expect(afterPause.distance == beforePause.distance)
        #expect(afterPause.score == beforePause.score)
        #expect(afterPause.trafficDensity == beforePause.trafficDensity)
        #expect(afterPause.stageProgress == beforePause.stageProgress)
        #expect(afterPause.timerRemaining == beforePause.timerRemaining)
    }

    @Test
    func runStateMachineCountsDownPausesAndRestartsWithoutAdvancingRaceTime() {
            var simulation = RaceSimulation(seed: 7, countdownDuration: 0.025)
            #expect(simulation.state.phase == .loading)

            simulation.advance(frameDelta: 1.0 / 120.0, command: .idle)
            #expect(simulation.state.phase == .countdown)
            #expect(simulation.state.elapsedTime == 0)

            for _ in 0..<4 {
                simulation.advance(frameDelta: 1.0 / 120.0, command: .idle)
            }
            #expect(simulation.state.phase == .racing)
            #expect(simulation.state.elapsedTime == 0)

            simulation.setPaused(true)
            #expect(simulation.state.phase == .paused)
            simulation.setPaused(false)
            #expect(simulation.state.phase == .racing)

            simulation.beginRestart()
            #expect(simulation.state.phase == .restarting)
            simulation.completeRestart(seed: 7)
            #expect(simulation.state.phase == .loading)
            #expect(simulation.state.distance == 0)
            #expect(simulation.state.completedStageIDs.isEmpty)
    }

    @Test
    func forkChoiceCheckpointAwardAndContinuityAreDeterministic() throws {
            let graph = forkTestGraph()
            let configuration = RaceConfiguration.testConfiguration(
                stageLength: 30,
                raceDuration: 10
            )
            var left = RaceSimulation(
                configuration: configuration,
                seed: 88,
                routeGraph: graph,
                countdownDuration: 0
            )
            var replay = RaceSimulation(
                configuration: configuration,
                seed: 88,
                routeGraph: graph,
                countdownDuration: 0
            )
            let command = PlayerCommand(steering: -1, throttle: 1, brake: 0, isBoosting: false)

            for _ in 0..<2_000 where left.state.currentStageID == "start" {
                left.advance(frameDelta: 1.0 / 120.0, command: command)
                replay.advance(frameDelta: 1.0 / 120.0, command: command)
            }

            #expect(left.state.currentStageID == "left")
            #expect(left.state.committedBranchIDs == ["choose-left"])
            #expect(left.state.completedStageIDs == ["start"])
            #expect(left.state.distance > 0)
            #expect(left.state.speed > 0)
            #expect(left.state.timerRemaining > configuration.raceDuration - left.state.elapsedTime)
            #expect(left.state == replay.state)
            #expect(left.runEvents == replay.runEvents)
            #expect(left.runEvents.contains { event in
                if case .checkpointCrossed(_, "start", "left", 4) = event { return true }
                return false
            })
    }

    @Test
    func rightForkCompletesThreeStageRouteAndPreservesTotalDistance() {
            let graph = forkTestGraph()
            let configuration = RaceConfiguration.testConfiguration(
                stageLength: 30,
                raceDuration: 20
            )
            var simulation = RaceSimulation(
                configuration: configuration,
                seed: 3,
                routeGraph: graph,
                countdownDuration: 0
            )
            let command = PlayerCommand(steering: 1, throttle: 1, brake: 0, isBoosting: false)

            for _ in 0..<10_000
            where simulation.state.phase != .finished && simulation.state.phase != .failed {
                simulation.advance(frameDelta: 1.0 / 120.0, command: command)
            }

            #expect(simulation.state.phase == .finished)
            #expect(simulation.state.committedBranchIDs == ["choose-right"])
            #expect(simulation.state.completedStageIDs == ["start", "right"])
            #expect(simulation.state.distance >= 30)
    }

    @Test
    func routeValidationRejectsMissingLinksAndInsufficientForkWarning() {
            let graph = RouteGraph(
                startStageID: "start",
                stages: [
                    RouteStage(
                        id: "start",
                        displayName: "Start",
                        environmentID: "city",
                        distance: 100,
                        checkpointTimeAward: 1,
                        branches: [
                            RouteBranch(
                                id: "missing",
                                direction: .left,
                                destinationStageID: "nowhere",
                                previewName: "Missing"
                            ),
                            RouteBranch(
                                id: "also-missing",
                                direction: .right,
                                destinationStageID: "void",
                                previewName: "Also Missing"
                            )
                        ]
                    )
                ],
                forkDecisionDistance: 10,
                minimumForkDecisionTime: 2
            )

            let errors = graph.validationErrors(maximumVehicleSpeed: 100)
            #expect(errors.contains(.missingDestination(stageID: "start", destinationID: "nowhere")))
            #expect(errors.contains(
                .forkDecisionDistanceTooShort(stageID: "start", required: 200, actual: 10)
            ))
            #expect(errors.contains(.forkLongerThanStage(stageID: "start")) == false)
            #expect(errors.contains(.noFinishStage))
    }

    @Test
    func slowFramesCapCatchUpStepsAndDropExcessTime() {
        var simulation = RaceSimulation(seed: 99)
        simulation.advance(frameDelta: 10, command: .idle)

        #expect(simulation.diagnostics.lastStepCount == RaceConfiguration.standard.maximumSimulationStepsPerFrame)
        #expect(simulation.diagnostics.droppedSimulationTime > 0)
    }

    @Test
    func timerExpirationFailsAndStopsFurtherUpdates() {
        let configuration = RaceConfiguration.testConfiguration(
            stageLength: 0.5,
            raceDuration: 1.0 / 120.0
        )
        var simulation = RaceSimulation(
            configuration: configuration,
            seed: 5,
            countdownDuration: 0
        )

        simulation.advance(frameDelta: 1.0 / 120.0, command: .idle)
        let terminalState = simulation.state
        simulation.advance(frameDelta: 1, command: PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: true))

        #expect(terminalState.phase == .failed)
        #expect(simulation.state == terminalState)
    }

    @Test
    func completingStageFinishesAndStopsFurtherUpdates() {
        let configuration = RaceConfiguration.testConfiguration(
            stageLength: 0.001,
            raceDuration: 10
        )
        var simulation = RaceSimulation(
            configuration: configuration,
            seed: 6,
            countdownDuration: 0
        )
        let command = PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false)

        simulation.advance(frameDelta: 1.0 / 120.0, command: command)
        let terminalState = simulation.state
        simulation.advance(frameDelta: 1, command: command)

        #expect(terminalState.phase == .finished)
        #expect(simulation.state == terminalState)
    }

    @Test
    func restartWithSameSeedReplaysIdenticalOutcome() {
        let commands = scriptedCommands(totalDuration: 12)
        var firstRun = RaceSimulation(seed: 1234)

        runSimulation(&firstRun, commands: commands, frameRate: 120)
        let expected = firstRun.state
        let expectedEvents = firstRun.events

        firstRun.restart(seed: 1234)
        runSimulation(&firstRun, commands: commands, frameRate: 120)

        #expect(firstRun.state == expected)
        #expect(firstRun.events == expectedEvents)
    }

    @Test
    func compactRecordedReplayReproducesFinalStateAndEvents() throws {
        let seed: UInt64 = 0xCAFE
        let commands = scriptedCommands(totalDuration: 12)
        let frameDelta = 1.0 / 60.0
        var simulation = RaceSimulation(seed: seed)
        var recorder = RaceReplayRecorder(seed: seed)
        var elapsed = 0.0

        while elapsed < 12 {
            let command = command(at: elapsed, segments: commands)
            try recorder.record(frameDelta: frameDelta, command: command)
            simulation.advance(frameDelta: frameDelta, command: command)
            elapsed += frameDelta
        }

        let replay = recorder.finish(events: simulation.events)
        let data = try JSONEncoder().encode(replay)
        let decoded = try JSONDecoder().decode(RaceReplay.self, from: data)
        let result = try RaceReplayExecutor.run(decoded)

        #expect(decoded == replay)
        #expect(
            result.finalState == simulation.state,
            "Replay seed \(seed), expected \(simulation.state), got \(result.finalState)"
        )
        #expect(
            result.events == simulation.events,
            "Replay seed \(seed), expected \(simulation.events), got \(result.events)"
        )
        #expect(result.frameCount == 720)
        #expect(replay.commandRuns.count == commands.count)

        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"v\":1"))
        #expect(json.contains("\"r\""))
        #expect(!json.contains("frameDelta"))
        #expect(data.count < 600)
    }

#if DEBUG
    @Test
    func debugRunSummaryRecordsLocalBalanceSignals() {
        var simulation = RaceSimulation(seed: 77, countdownDuration: 0)
        let command = PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: true)

        for _ in 0..<360 {
            simulation.advance(frameDelta: 1.0 / 120.0, command: command)
        }
        simulation.ingest(.collision(id: 0xC011, severity: 0.5))

        let summary = simulation.developmentRunSummary
        #expect(summary.speedDistribution.maximum > summary.speedDistribution.minimum)
        #expect(summary.boostActivationCount == 1)
        #expect(summary.boostActiveTime > 0)
        #expect(summary.scoreBySource[.distance, default: 0] > 0)
        #expect(summary.scoreBySource[.collision, default: 0] < 0)
    }
#endif

    @Test
    func replayDetectsEventSequenceMismatch() throws {
        let run = try RaceCommandRun(
            frameDelta: 1.0 / 120.0,
            repeatCount: 1,
            command: .idle
        )
        let replay = RaceReplay(
            seed: 1,
            commandRuns: [run],
            events: [.finished(time: 0)]
        )

        #expect(throws: RaceReplayError.self) {
            try RaceReplayExecutor.run(replay)
        }
    }

    @Test(arguments: [
        #"{"v":2,"s":1,"r":[]}"#,
        #"{"v":1,"s":1,"r":[{"d":-0.1,"n":1,"c":{"s":0,"t":0,"b":0,"x":false}}]}"#,
        #"{"v":1,"s":1,"r":[{"d":0.016,"n":0,"c":{"s":0,"t":0,"b":0,"x":false}}]}"#
    ])
    func malformedReplayFixturesAreRejected(fixture: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RaceReplay.self, from: Data(fixture.utf8))
        }
    }

    @Test
    func recorderRejectsNonfiniteInputs() {
        var recorder = RaceReplayRecorder(seed: 1)

        #expect(throws: RaceReplayError.invalidFrameDelta) {
            try recorder.record(frameDelta: .nan, command: .idle)
        }
        #expect(throws: RaceReplayError.invalidCommand) {
            try recorder.record(
                frameDelta: 1.0 / 60.0,
                command: PlayerCommand(
                    steering: .nan,
                    throttle: 1,
                    brake: 0,
                    isBoosting: false
                )
            )
        }
        #expect(recorder.commandRuns.isEmpty)
    }

    @Test
    func commandsAreClampedToSimulationInvariants() {
        var simulation = RaceSimulation(seed: 31)
        let extreme = PlayerCommand(
            steering: 100,
            throttle: 100,
            brake: -100,
            isBoosting: false
        )

        for _ in 0..<10_000 {
            simulation.advance(frameDelta: 1.0 / 120.0, command: extreme)
        }

        #expect(simulation.state.speed >= 0)
        #expect(simulation.state.speed <= RaceConfiguration.standard.maximumSpeed)
        #expect(abs(simulation.state.lateralPosition) <= RaceConfiguration.standard.driving.lateralLimit)
        #expect(simulation.state.stageProgress >= 0)
        #expect(simulation.state.stageProgress <= 1)
        #expect(simulation.state.timerRemaining >= 0)
    }

    @Test
    func renderSnapshotProvidesBoundedInterpolationAlpha() {
        var simulation = RaceSimulation(seed: 11)
        simulation.advance(frameDelta: 1.0 / 240.0, command: .idle)

        let snapshot = simulation.renderSnapshot
        #expect(snapshot.interpolationAlpha >= 0)
        #expect(snapshot.interpolationAlpha <= 1)
    }

    private func runSimulation(
        _ simulation: inout RaceSimulation,
        commands: [CommandSegment],
        frameRate: Int
    ) {
        let frameDelta = 1.0 / Double(frameRate)
        let totalDuration = commands.map(\ .duration).reduce(0, +)
        let frameCount = Int((totalDuration * Double(frameRate)).rounded())

        for frame in 0..<frameCount {
            let elapsed = Double(frame) * frameDelta
            let command = command(at: elapsed, segments: commands)
            simulation.advance(frameDelta: frameDelta, command: command)
        }
    }

    private func command(at elapsed: TimeInterval, segments: [CommandSegment]) -> PlayerCommand {
        var cursor: TimeInterval = 0
        for segment in segments {
            let next = cursor + segment.duration
            if elapsed < next {
                return segment.command
            }
            cursor = next
        }
        return segments.last?.command ?? .idle
    }

    private func scriptedCommands(totalDuration: TimeInterval) -> [CommandSegment] {
        [
            CommandSegment(duration: totalDuration * 0.20, command: PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false)),
            CommandSegment(duration: totalDuration * 0.15, command: PlayerCommand(steering: 0.35, throttle: 1, brake: 0, isBoosting: false)),
            CommandSegment(duration: totalDuration * 0.15, command: PlayerCommand(steering: -0.5, throttle: 0.8, brake: 0, isBoosting: true)),
            CommandSegment(duration: totalDuration * 0.10, command: PlayerCommand(steering: 0, throttle: 0, brake: 1, isBoosting: false)),
            CommandSegment(duration: totalDuration * 0.40, command: PlayerCommand(steering: 0.1, throttle: 1, brake: 0, isBoosting: true))
        ]
    }

    private func assertStatesEquivalent(_ lhs: RaceState, _ rhs: RaceState) {
        let oneFixedStep = RaceConfiguration.standard.fixedTimeStep
        #expect(abs(lhs.elapsedTime - rhs.elapsedTime) <= oneFixedStep + 0.000_001)
        #expect(abs(lhs.distance - rhs.distance) < 1)
        #expect(abs(lhs.speed - rhs.speed) < 0.5)
        #expect(abs(lhs.lateralPosition - rhs.lateralPosition) < 0.01)
        #expect(abs(lhs.score - rhs.score) < 1)
        #expect(abs(lhs.stageProgress - rhs.stageProgress) < 0.001)
    }

    private func forkTestGraph() -> RouteGraph {
        RouteGraph(
            startStageID: "start",
            stages: [
                RouteStage(
                    id: "start",
                    displayName: "Start",
                    environmentID: "city",
                    distance: 10,
                    checkpointTimeAward: 4,
                    branches: [
                        RouteBranch(
                            id: "choose-left",
                            direction: .left,
                            destinationStageID: "left",
                            previewName: "Left"
                        ),
                        RouteBranch(
                            id: "choose-right",
                            direction: .right,
                            destinationStageID: "right",
                            previewName: "Right"
                        )
                    ]
                ),
                RouteStage(
                    id: "left",
                    displayName: "Left",
                    environmentID: "harbor",
                    distance: 10,
                    checkpointTimeAward: 2,
                    branches: [
                        RouteBranch(
                            id: "left-finish",
                            direction: .straight,
                            destinationStageID: "finish",
                            previewName: "Finish"
                        )
                    ]
                ),
                RouteStage(
                    id: "right",
                    displayName: "Right",
                    environmentID: "skyway",
                    distance: 10,
                    checkpointTimeAward: 3,
                    branches: [
                        RouteBranch(
                            id: "right-finish",
                            direction: .straight,
                            destinationStageID: "finish",
                            previewName: "Finish"
                        )
                    ]
                ),
                RouteStage(
                    id: "finish",
                    displayName: "Finish",
                    environmentID: "core",
                    distance: 10,
                    checkpointTimeAward: 0,
                    branches: []
                )
            ],
            forkDecisionDistance: 5,
            minimumForkDecisionTime: 0
        )
    }
}

private struct CommandSegment {
    let duration: TimeInterval
    let command: PlayerCommand
}

private extension RaceConfiguration {
    func withTrafficSpawningEnabled(_ enabled: Bool) -> RaceConfiguration {
        RaceConfiguration(
            fixedTimeStep: fixedTimeStep,
            maximumFrameDelta: maximumFrameDelta,
            maximumSimulationStepsPerFrame: maximumSimulationStepsPerFrame,
            acceleration: acceleration,
            braking: braking,
            drag: drag,
            maximumSpeed: maximumSpeed,
            steeringRate: steeringRate,
            driving: driving,
            crashPenalties: crashPenalties,
            stageLength: stageLength,
            raceDuration: raceDuration,
            profile: profile,
            traffic: traffic.withSpawningEnabled(enabled),
            boost: boost,
            scoring: scoring
        )
    }

    static func testConfiguration(
        stageLength: Double,
        raceDuration: TimeInterval
    ) -> RaceConfiguration {
        let theoreticalBoostTime = min(
            raceDuration,
            (standard.boost.initialCharge + standard.boost.rechargePerSecond * raceDuration)
                / (standard.boost.consumptionPerSecond + standard.boost.rechargePerSecond)
        )
        let maximumScore =
            stageLength * standard.scoring.pointsPerDistance
            + theoreticalBoostTime * standard.scoring.pointsPerBoostSecond
        let scoring = ScoringBalance(
            pointsPerDistance: standard.scoring.pointsPerDistance,
            pointsPerBoostSecond: standard.scoring.pointsPerBoostSecond,
            bronzeThreshold: maximumScore * 0.5,
            silverThreshold: maximumScore * 0.7,
            goldThreshold: maximumScore * 0.9
        )

        return RaceConfiguration(
            fixedTimeStep: standard.fixedTimeStep,
            maximumFrameDelta: standard.maximumFrameDelta,
            maximumSimulationStepsPerFrame: standard.maximumSimulationStepsPerFrame,
            acceleration: standard.acceleration,
            braking: standard.braking,
            drag: standard.drag,
            maximumSpeed: standard.maximumSpeed,
            steeringRate: standard.steeringRate,
            driving: standard.driving,
            crashPenalties: standard.crashPenalties,
            stageLength: stageLength,
            raceDuration: raceDuration,
            profile: standard.profile,
            traffic: standard.traffic,
            boost: standard.boost,
            scoring: scoring
        )
    }
}
