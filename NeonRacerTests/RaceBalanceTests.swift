import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct RaceBalanceTests {
    @Test
    func shippedProfilesAreValidAndIncreaseTrafficPressure() {
        let profiles = DifficultyProfile.allCases.map {
            RaceConfiguration.configuration(for: $0)
        }

        for configuration in profiles {
            #expect(configuration.validationErrors.isEmpty)
        }

        #expect(RaceConfiguration.novice.traffic.maximumDensity
            < RaceConfiguration.standard.traffic.maximumDensity)
        #expect(RaceConfiguration.standard.traffic.maximumDensity
            < RaceConfiguration.expert.traffic.maximumDensity)
        #expect(RaceConfiguration.novice.raceDuration
            > RaceConfiguration.standard.raceDuration)
        #expect(RaceConfiguration.standard.raceDuration
            > RaceConfiguration.expert.raceDuration)
    }

    @Test
    func validationRejectsUnorderedRankThresholds() {
        let invalid = RaceConfiguration.copyOfStandard(
            scoring: ScoringBalance(
                pointsPerDistance: 1,
                pointsPerBoostSecond: 25,
                bronzeThreshold: 5_000,
                silverThreshold: 4_000,
                goldThreshold: 6_000
            )
        )

        #expect(invalid.validationErrors.contains(.rankThresholdsNotStrictlyIncreasing))
    }

    @Test
    func boostIsFiniteImprovesPerformanceAndRechargesWhenReleased() {
        var boosted = RaceSimulation(seed: 50, countdownDuration: 0)
        var unboosted = RaceSimulation(seed: 50, countdownDuration: 0)
        let boostCommand = PlayerCommand(
            steering: 0,
            throttle: 1,
            brake: 0,
            isBoosting: true
        )
        let throttleCommand = PlayerCommand(
            steering: 0,
            throttle: 1,
            brake: 0,
            isBoosting: false
        )

        advance(&boosted, seconds: 6, command: boostCommand)
        advance(&unboosted, seconds: 6, command: throttleCommand)

        #expect(boosted.state.boostCharge == 0)
        #expect(boosted.state.scoreInputs.boostTime <= 4.01)
        #expect(boosted.state.distance > unboosted.state.distance)
        #expect(boosted.state.score > unboosted.state.score)

        advance(&boosted, seconds: 10, command: throttleCommand)

        #expect(abs(boosted.state.boostCharge - 3) < 0.01)
        #expect(boosted.state.boostCharge <= RaceConfiguration.standard.boost.capacity)
    }

    @Test
    func brakingCannotFarmBoostScore() {
        var simulation = RaceSimulation(seed: 5)
        let initialCharge = simulation.state.boostCharge

        advance(
            &simulation,
            seconds: 2,
            command: PlayerCommand(
                steering: 0,
                throttle: 1,
                brake: 1,
                isBoosting: true
            )
        )

        #expect(simulation.state.scoreInputs.boostTime == 0)
        #expect(simulation.state.scoreInputs.boostPoints == 0)
        #expect(simulation.state.boostCharge == initialCharge)
    }

    @Test
    func trafficDensityStaysInsideConfiguredEnvelope() {
        for configuration in [
            RaceConfiguration.novice,
            RaceConfiguration.standard,
            RaceConfiguration.expert
        ] {
            var simulation = RaceSimulation(configuration: configuration, seed: 99)
            for _ in 0..<1_200 {
                simulation.advance(
                    frameDelta: 1.0 / 120.0,
                    command: PlayerCommand(
                        steering: 0,
                        throttle: 1,
                        brake: 0,
                        isBoosting: false
                    )
                )
                #expect(simulation.state.trafficDensity >= configuration.traffic.baseDensity)
                #expect(simulation.state.trafficDensity <= configuration.traffic.maximumDensity)
            }
        }
    }

    @Test
    func rankThresholdsHaveExactStableBoundaries() {
        let scoring = RaceConfiguration.standard.scoring

        #expect(scoring.rank(for: scoring.bronzeThreshold - 0.01) == .unranked)
        #expect(scoring.rank(for: scoring.bronzeThreshold) == .bronze)
        #expect(scoring.rank(for: scoring.silverThreshold) == .silver)
        #expect(scoring.rank(for: scoring.goldThreshold) == .gold)
    }

    @Test
    func representativeRunsMapToBronzeSilverAndGold() {
        for configuration in [
            RaceConfiguration.novice,
            RaceConfiguration.standard,
            RaceConfiguration.expert
        ] {
            let noBoost = completedRun(configuration: configuration) { _ in false }
            let initialBoost = completedRun(configuration: configuration) { _ in true }
            let managedBoost = completedRun(configuration: configuration) { frame in
                frame % (9 * 120) < 3 * 120
            }
            #expect(noBoost.phase == .finished)
            #expect(initialBoost.phase == .finished)
            #expect(managedBoost.phase == .finished)
            #expect(configuration.scoring.rank(for: noBoost.score) == .bronze)
            #expect(configuration.scoring.rank(for: initialBoost.score) == .silver)
            #expect(configuration.scoring.rank(for: managedBoost.score) == .gold)
        }
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

    private func completedRun(
        configuration: RaceConfiguration,
        shouldBoost: (Int) -> Bool
    ) -> RaceState {
        let scriptedConfiguration = configuration.withTrafficSpawningEnabled(false)
        var simulation = RaceSimulation(configuration: scriptedConfiguration, seed: 1)
        var frame = 0
        while simulation.state.phase != .finished && simulation.state.phase != .failed {
            simulation.advance(
                frameDelta: 1.0 / 120.0,
                command: PlayerCommand(
                    steering: followRoadSteering(
                        state: simulation.state,
                        layout: simulation.trackLayout,
                        configuration: configuration
                    ),
                    throttle: 1,
                    brake: 0,
                    isBoosting: shouldBoost(frame)
                )
            )
            frame += 1
        }
        return simulation.state
    }

    private func followRoadSteering(
        state: RaceState,
        layout: TrackLayout,
        configuration: RaceConfiguration
    ) -> Double {
        let sample = layout.sample(
            stageID: state.currentStageID,
            distanceInStage: state.currentStageDistance
        )
        let rawSpeedRatio = state.speed / configuration.maximumSpeed
        let speedRatio = min(max(rawSpeedRatio, 0), 1)
        let motionGate = min(max(state.speed / 8, 0), 1)
        let authority = (
            configuration.driving.steeringAtRestRatio
                + (1 - configuration.driving.steeringAtRestRatio) * speedRatio
        ) * motionGate
        let counterSteer = sample.curvature
            * state.speed
            * state.speed
            * configuration.driving.centrifugalForce
            / max(0.1, configuration.steeringRate * authority)
        let recenter = -state.lateralPosition * 1.35
        return min(max(counterSteer + recenter, -1), 1)
    }
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

    static func copyOfStandard(scoring: ScoringBalance) -> RaceConfiguration {
        RaceConfiguration(
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
            stageLength: standard.stageLength,
            raceDuration: standard.raceDuration,
            profile: standard.profile,
            traffic: standard.traffic,
            boost: standard.boost,
            scoring: scoring
        )
    }

}
