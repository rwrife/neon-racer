import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct RaceSimulationTests {
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

        var atThirty = RaceSimulation(seed: 42)
        var atSixty = RaceSimulation(seed: 42)
        var atOneTwenty = RaceSimulation(seed: 42)

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
        var simulation = RaceSimulation(configuration: configuration, seed: 5)

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
        var simulation = RaceSimulation(configuration: configuration, seed: 6)
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
        #expect(simulation.state.lateralPosition == 1)
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
        var elapsed = 0.0
        let totalDuration = commands.map(\ .duration).reduce(0, +)

        while elapsed < totalDuration {
            let command = command(at: elapsed, segments: commands)
            simulation.advance(frameDelta: frameDelta, command: command)
            elapsed += frameDelta
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
}

private struct CommandSegment {
    let duration: TimeInterval
    let command: PlayerCommand
}

private extension RaceConfiguration {
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
            stageLength: stageLength,
            raceDuration: raceDuration,
            profile: standard.profile,
            traffic: standard.traffic,
            boost: standard.boost,
            scoring: scoring
        )
    }
}
