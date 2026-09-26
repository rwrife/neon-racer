import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct RaceSimulationTests {
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
            stageLength: 10_000,
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

        firstRun.restart(seed: 1234)
        runSimulation(&firstRun, commands: commands, frameRate: 120)

        #expect(firstRun.state == expected)
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
        RaceConfiguration(
            fixedTimeStep: standard.fixedTimeStep,
            maximumFrameDelta: standard.maximumFrameDelta,
            maximumSimulationStepsPerFrame: standard.maximumSimulationStepsPerFrame,
            acceleration: standard.acceleration,
            braking: standard.braking,
            drag: standard.drag,
            maximumSpeed: standard.maximumSpeed,
            steeringRate: standard.steeringRate,
            stageLength: stageLength,
            raceDuration: raceDuration
        )
    }
}

