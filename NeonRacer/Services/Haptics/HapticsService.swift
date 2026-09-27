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

        guard let pattern = try? event.pattern(intensityScale: settings.intensity) else {
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
            duration: 1
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
    func pattern(intensityScale: Double) throws -> CHHapticPattern {
        let scale = Float(min(max(intensityScale, 0), 1))
        return try CHHapticPattern(
            events: events(intensityScale: scale),
            parameterCurves: parameterCurves(intensityScale: scale)
        )
    }

    func events(intensityScale scale: Float) -> [CHHapticEvent] {
        switch self {
        case .roadSurface:
            [
                Self.continuous(intensity: 0.18 * scale, sharpness: 0.12, time: 0, duration: 0.16)
            ]
        case .drift:
            [
                Self.continuous(intensity: 0.36 * scale, sharpness: 0.32, time: 0, duration: 0.28),
                Self.transient(intensity: 0.24 * scale, sharpness: 0.7, time: 0.06),
                Self.transient(intensity: 0.2 * scale, sharpness: 0.65, time: 0.18)
            ]
        case .nearMiss:
            [
                Self.transient(intensity: 0.52 * scale, sharpness: 0.9, time: 0),
                Self.transient(intensity: 0.32 * scale, sharpness: 0.75, time: 0.08)
            ]
        case .boost:
            [
                Self.transient(intensity: 0.72 * scale, sharpness: 0.58, time: 0),
                Self.continuous(intensity: 0.44 * scale, sharpness: 0.42, time: 0.03, duration: 0.22)
            ]
        case .checkpoint:
            [
                Self.transient(intensity: 0.52 * scale, sharpness: 0.82, time: 0),
                Self.transient(intensity: 0.42 * scale, sharpness: 0.92, time: 0.12),
                Self.transient(intensity: 0.36 * scale, sharpness: 0.86, time: 0.24)
            ]
        case .collision:
            [
                Self.transient(intensity: 1.0 * scale, sharpness: 0.16, time: 0),
                Self.continuous(intensity: 0.45 * scale, sharpness: 0.12, time: 0.02, duration: 0.18)
            ]
        }
    }

    func parameterCurves(intensityScale scale: Float) -> [CHHapticParameterCurve] {
        switch self {
        case .roadSurface:
            [
                Self.intensityCurve([
                    .init(relativeTime: 0, value: 0.08 * scale),
                    .init(relativeTime: 0.04, value: 0.2 * scale),
                    .init(relativeTime: 0.1, value: 0.12 * scale),
                    .init(relativeTime: 0.16, value: 0.03 * scale)
                ])
            ]
        case .boost:
            [
                Self.intensityCurve([
                    .init(relativeTime: 0.03, value: 0.28 * scale),
                    .init(relativeTime: 0.11, value: 0.62 * scale),
                    .init(relativeTime: 0.25, value: 0.08 * scale)
                ])
            ]
        case .collision:
            [
                Self.intensityCurve([
                    .init(relativeTime: 0.02, value: 0.6 * scale),
                    .init(relativeTime: 0.1, value: 0.32 * scale),
                    .init(relativeTime: 0.2, value: 0.02 * scale)
                ])
            ]
        case .drift, .nearMiss, .checkpoint:
            []
        }
    }

    static func transient(intensity: Float, sharpness: Float, time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: parameters(intensity: intensity, sharpness: sharpness),
            relativeTime: time
        )
    }

    static func continuous(
        intensity: Float,
        sharpness: Float,
        time: TimeInterval,
        duration: TimeInterval
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: parameters(intensity: intensity, sharpness: sharpness),
            relativeTime: time,
            duration: duration
        )
    }

    static func parameters(intensity: Float, sharpness: Float) -> [CHHapticEventParameter] {
        [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: min(max(intensity, 0), 1)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: min(max(sharpness, 0), 1))
        ]
    }

    static func intensityCurve(
        _ points: [CHHapticParameterCurve.ControlPoint]
    ) -> CHHapticParameterCurve {
        CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: points,
            relativeTime: 0
        )
    }
}
