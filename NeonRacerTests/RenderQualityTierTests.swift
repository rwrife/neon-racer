import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct RenderQualityTierTests {
    @Test
    func automaticSelectionUsesSimulatorMedium() {
        let profile = RenderQualityDeviceProfile(
            physicalMemoryBytes: 32 * 1_073_741_824,
            thermalState: .nominal,
            isSimulator: true
        )

        let selected = RenderQualityConfiguration.selected(preference: .automatic, deviceProfile: profile)

        #expect(selected.tier == .medium)
        #expect(selected.antialiasing == .multisampling2X)
    }

    @Test
    func automaticSelectionUsesMemoryBands() {
        let low = RenderQualityDeviceProfile(physicalMemoryBytes: 3 * 1_073_741_824, thermalState: .nominal, isSimulator: false)
        let medium = RenderQualityDeviceProfile(physicalMemoryBytes: 4 * 1_073_741_824, thermalState: .nominal, isSimulator: false)
        let high = RenderQualityDeviceProfile(physicalMemoryBytes: 6 * 1_073_741_824, thermalState: .nominal, isSimulator: false)

        #expect(RenderQualityConfiguration.selected(preference: .automatic, deviceProfile: low).tier == .low)
        #expect(RenderQualityConfiguration.selected(preference: .automatic, deviceProfile: medium).tier == .medium)
        #expect(RenderQualityConfiguration.selected(preference: .automatic, deviceProfile: high).tier == .high)
    }

    @Test
    func explicitPreferenceIsThermallyCapped() {
        let fair = RenderQualityDeviceProfile(physicalMemoryBytes: 8 * 1_073_741_824, thermalState: .fair, isSimulator: false)
        let serious = RenderQualityDeviceProfile(physicalMemoryBytes: 8 * 1_073_741_824, thermalState: .serious, isSimulator: false)

        #expect(RenderQualityConfiguration.selected(preference: .high, deviceProfile: fair).tier == .medium)
        #expect(RenderQualityConfiguration.selected(preference: .high, deviceProfile: serious).tier == .low)
    }

    @Test
    func budgetsScaleMonotonicallyWithTier() {
        let presets = RenderQualityTier.allCases.map(RenderQualityConfiguration.preset)

        #expect(isNondecreasing(presets.map(\.contentScale)))
        #expect(isNondecreasing(presets.map(\.particleDensityScale)))
        #expect(isNondecreasing(presets.map(\.sceneryDensityScale)))
        #expect(isNondecreasing(presets.map(\.drawDistanceMeters)))
        #expect(presets[0].postProcessingEnabled == false)
        #expect(presets[2].postProcessingEnabled == true)
    }

    private func isNondecreasing(_ values: [Double]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy(<=)
    }
}
