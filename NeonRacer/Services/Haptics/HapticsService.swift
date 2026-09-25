import CoreHaptics

@MainActor
final class HapticsService {
    private var engine: CHHapticEngine?

    func prepare() throws {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }

        let engine = try CHHapticEngine()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        engine?.stop()
        engine = nil
    }
}

