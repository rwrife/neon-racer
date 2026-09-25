import Testing
@testable import NeonRacer

struct RaceSimulationTests {
    @Test
    func identicalFrameStreamsProduceIdenticalState() {
        var first = RaceSimulation()
        var second = RaceSimulation()
        let command = PlayerCommand(
            steering: 0.25,
            throttle: 1,
            brake: 0,
            isBoosting: false
        )

        for _ in 0..<600 {
            first.advance(frameDelta: 1.0 / 60.0, command: command)
            second.advance(frameDelta: 1.0 / 60.0, command: command)
        }

        #expect(first.state == second.state)
    }

    @Test
    func speedNeverExceedsConfiguredMaximum() {
        var simulation = RaceSimulation()
        let command = PlayerCommand(
            steering: 0,
            throttle: 1,
            brake: 0,
            isBoosting: false
        )

        for _ in 0..<3_600 {
            simulation.advance(frameDelta: 1.0 / 60.0, command: command)
        }

        #expect(simulation.state.speed == RaceConfiguration.standard.maximumSpeed)
    }

    @Test
    func resetRestoresInitialState() {
        var simulation = RaceSimulation()
        simulation.advance(
            frameDelta: 1,
            command: PlayerCommand(
                steering: 1,
                throttle: 1,
                brake: 0,
                isBoosting: false
            )
        )

        simulation.reset()

        #expect(simulation.state == RaceState())
    }
}

