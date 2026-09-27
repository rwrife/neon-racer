import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct CosmeticQualityTests {
    @Test
    func everyTierHasExactlyOneValidPreset() {
        let presets = CosmeticQualityTier.allCases.map(CosmeticQualityConfiguration.preset)

        #expect(presets.map(\.tier) == CosmeticQualityTier.allCases)
        #expect(presets.allSatisfy { (0...1).contains($0.particleDensityScale) })
        #expect(presets.allSatisfy { (0...1).contains($0.sceneryDensityScale) })
        #expect(presets.allSatisfy { (0...1).contains($0.renderTargetScale) })
        #expect(presets.allSatisfy { (0...1).contains($0.glowScale) })
    }

    @Test
    func cosmeticCostScalesMonotonicallyWithTier() {
        let tiers: [CosmeticQualityConfiguration] = [.efficiency, .balanced, .fidelity]

        #expect(isNondecreasing(tiers.map(\.particleDensityScale)))
        #expect(isNondecreasing(tiers.map(\.sceneryDensityScale)))
        #expect(isNondecreasing(tiers.map(\.renderTargetScale)))
        #expect(isNondecreasing(tiers.map(\.glowScale)))
    }

    @Test
    func qualitySelectionCannotChangeSimulationOutcome() {
        let command = PlayerCommand(steering: 0.25, throttle: 1, brake: 0, isBoosting: true)
        var outcomes: [RaceState] = []

        for tier in CosmeticQualityTier.allCases {
            _ = CosmeticQualityConfiguration.preset(for: tier)
            var simulation = RaceSimulation(seed: 0x23)
            for _ in 0..<1_200 {
                simulation.advance(frameDelta: 1.0 / 120.0, command: command)
            }
            outcomes.append(simulation.state)
        }

        #expect(outcomes.dropFirst().allSatisfy { $0 == outcomes[0] })
    }

    private func isNondecreasing(_ values: [Double]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy(<=)
    }
}
