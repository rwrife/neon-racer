import CoreHaptics
import UIKit

enum HapticEvent: Sendable {
    case roadSurface
    case drift
    case nearMiss
    case boost
    case checkpoint
    case collision
}

@MainActor
final class HapticsService {
    private var engine: CHHapticEngine?
    private var enginePlayer: CHHapticAdvancedPatternPlayer?
    private var settings = HapticSettings.standard

    var supportsCoreHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    func prepare() throws {
        guard settings.isEnabled, engine == nil else {
            return
        }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }

        let engine = try CHHapticEngine()
        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.enginePlayer = nil }
        }
        engine.resetHandler = { [weak self] in
            Task { @MainActor in
                self?.enginePlayer = nil
                self?.engine = nil
            }
        }
        try engine.start()
        self.engine = engine
    }

    func configure(_ settings: HapticSettings) {
        self.settings = HapticSettings(
            isEnabled: settings.isEnabled,
            intensity: min(max(settings.intensity, 0), 1)
        )
        if !self.settings.isEnabled {
            stop()
        }
    }

    func play(_ event: HapticEvent) {
        guard settings.isEnabled else {
            return
        }
        try? prepare()
        guard let engine else {
            playFallback(event)
            return
        }

        let parameters = event.parameters
        let hapticEvent = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(
                    parameterID: .hapticIntensity,
                    value: Float(parameters.intensity * settings.intensity)
                ),
                CHHapticEventParameter(
                    parameterID: .hapticSharpness,
                    value: Float(parameters.sharpness)
                )
            ],
            relativeTime: 0
        )
        guard let pattern = try? CHHapticPattern(events: [hapticEvent], parameters: []) else {
            return
        }
        try? engine.makePlayer(with: pattern).start(atTime: 0)
    }

    func updateEngine(intensity: Double) {
        guard settings.isEnabled else {
            stopEngineTexture()
            return
        }
        try? prepare()
        guard let engine else {
            return
        }

        let value = Float(min(max(intensity, 0), 1) * settings.intensity)
        if value <= 0.01 {
            stopEngineTexture()
            return
        }

        if let enginePlayer {
            let parameter = CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: value,
                relativeTime: 0
            )
            try? enginePlayer.sendParameters([parameter], atTime: 0)
            return
        }

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: value),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
            ],
            relativeTime: 0,
            duration: 30
        )
        guard
            let pattern = try? CHHapticPattern(events: [event], parameters: []),
            let player = try? engine.makeAdvancedPlayer(with: pattern)
        else {
            return
        }
        player.loopEnabled = true
        enginePlayer = player
        try? player.start(atTime: 0)
    }

    func stopEngineTexture() {
        try? enginePlayer?.stop(atTime: 0)
        enginePlayer = nil
    }

    func stop() {
        stopEngineTexture()
        engine?.stop()
        engine = nil
    }

    func suspend() {
        stop()
    }

    private func playFallback(_ event: HapticEvent) {
        switch event {
        case .collision:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .checkpoint:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .boost, .drift, .nearMiss, .roadSurface:
            let style: UIImpactFeedbackGenerator.FeedbackStyle =
                event == .boost ? .heavy : .medium
            UIImpactFeedbackGenerator(style: style).impactOccurred(
                intensity: settings.intensity
            )
        }
    }
}

private extension HapticEvent {
    var parameters: (intensity: Double, sharpness: Double) {
        switch self {
        case .roadSurface: (0.18, 0.1)
        case .drift: (0.45, 0.35)
        case .nearMiss: (0.6, 0.8)
        case .boost: (0.85, 0.55)
        case .checkpoint: (0.7, 0.9)
        case .collision: (1, 0.2)
        }
    }
}
