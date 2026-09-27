import Foundation

enum AudioBus: String, CaseIterable, Codable, Sendable {
    case music
    case engine
    case tires
    case ambience
    case impacts
    case ui
    case voice
}

enum AdaptiveMusicSection: String, Codable, Equatable, Sendable {
    case menu
    case countdown
    case racing
    case intense
    case finish
    case failure
}

enum AudioEnvironment: String, Codable, Equatable, Sendable {
    case city
    case coast
    case desert
    case tunnel
}

enum AudioEvent: Equatable, Sendable {
    case showMenu
    case raceStarted
    case racePaused
    case raceResumed
    case raceRetried
    case raceExited
    case checkpoint
    case pass
    case nearMiss
    case combo
    case boost
    case crash(severity: Double)
    case finish
    case failure
    case uiConfirm
    case environmentChanged(AudioEnvironment)
}

struct AudioPreferences: Codable, Equatable, Sendable {
    var musicLevel: Double
    var effectsLevel: Double
    var isMusicMuted: Bool
    var areEffectsMuted: Bool

    static let standard = AudioPreferences(
        musicLevel: 0.72,
        effectsLevel: 0.85,
        isMusicMuted: false,
        areEffectsMuted: false
    )

    init(
        musicLevel: Double,
        effectsLevel: Double,
        isMusicMuted: Bool,
        areEffectsMuted: Bool
    ) {
        self.musicLevel = musicLevel.clamped(to: 0...1)
        self.effectsLevel = effectsLevel.clamped(to: 0...1)
        self.isMusicMuted = isMusicMuted
        self.areEffectsMuted = areEffectsMuted
    }

    func gain(for bus: AudioBus) -> Double {
        switch bus {
        case .music:
            isMusicMuted ? 0 : musicLevel
        case .engine, .tires, .ambience, .impacts, .ui, .voice:
            areEffectsMuted ? 0 : effectsLevel
        }
    }
}

struct EngineAudioInput: Equatable, Sendable {
    var normalizedRPM: Double
    var normalizedSpeed: Double
    var throttle: Double
    var drift: Double
    var boost: Double
    var offRoad: Double
    var collisionRecovery: Double

    static let idle = EngineAudioInput(
        normalizedRPM: 0,
        normalizedSpeed: 0,
        throttle: 0,
        drift: 0,
        boost: 0,
        offRoad: 0,
        collisionRecovery: 0
    )
}

struct EngineAudioOutput: Equatable, Sendable {
    var pitchRate: Double = 0.72
    var engineGain: Double = 0
    var tireGain: Double = 0
    var ambienceGain: Double = 0
}

struct AudioMixState: Equatable, Sendable {
    private(set) var preferences: AudioPreferences
    private(set) var musicSection: AdaptiveMusicSection = .menu
    private(set) var environment: AudioEnvironment = .city
    private(set) var engine = EngineAudioOutput()
    private(set) var isRaceActive = false
    private(set) var isPaused = false
    private(set) var isApplicationActive = true
    private(set) var isInterrupted = false

    init(preferences: AudioPreferences = .standard) {
        self.preferences = preferences
    }

    var shouldRender: Bool {
        isApplicationActive && !isInterrupted
    }

    var shouldPlayMusic: Bool {
        shouldRender && !isPaused
    }

    var shouldPlayVehicleAudio: Bool {
        shouldRender && isRaceActive && !isPaused
    }

    mutating func setPreferences(_ preferences: AudioPreferences) {
        self.preferences = preferences
    }

    mutating func setApplicationActive(_ active: Bool) {
        isApplicationActive = active
    }

    mutating func setInterrupted(_ interrupted: Bool) {
        isInterrupted = interrupted
    }

    mutating func handle(_ event: AudioEvent) {
        switch event {
        case .showMenu:
            isRaceActive = false
            isPaused = false
            musicSection = .menu
        case .raceStarted, .raceRetried:
            isRaceActive = true
            isPaused = false
            musicSection = .countdown
            engine = EngineAudioOutput()
        case .racePaused:
            isPaused = true
        case .raceResumed:
            isPaused = false
        case .raceExited:
            isRaceActive = false
            isPaused = false
            musicSection = .menu
            engine = EngineAudioOutput()
        case .checkpoint:
            musicSection = .intense
        case .boost:
            if isRaceActive {
                musicSection = .intense
            }
        case .finish:
            isRaceActive = false
            musicSection = .finish
        case .failure:
            isRaceActive = false
            musicSection = .failure
        case let .environmentChanged(environment):
            self.environment = environment
        case .pass, .nearMiss, .combo, .crash, .uiConfirm:
            break
        }
    }

    mutating func advanceEngine(
        input: EngineAudioInput,
        deltaTime: TimeInterval
    ) {
        let rpm = input.normalizedRPM.clamped(to: 0...1)
        let speed = input.normalizedSpeed.clamped(to: 0...1)
        let throttle = input.throttle.clamped(to: 0...1)
        let drift = input.drift.clamped(to: 0...1)
        let boost = input.boost.clamped(to: 0...1)
        let offRoad = input.offRoad.clamped(to: 0...1)
        let recovery = input.collisionRecovery.clamped(to: 0...1)

        if musicSection == .countdown, speed > 0.08 {
            musicSection = .racing
        }

        let target = EngineAudioOutput(
            pitchRate: 0.72 + rpm * 0.9 + boost * 0.14 - recovery * 0.12,
            engineGain: (0.14 + speed * 0.42 + throttle * 0.28 + boost * 0.12)
                .clamped(to: 0...0.9),
            tireGain: (drift * 0.7 + offRoad * 0.42).clamped(to: 0...0.72),
            ambienceGain: (0.12 + speed * 0.32).clamped(to: 0...0.5)
        )

        let attack = smoothingFactor(deltaTime: deltaTime, timeConstant: 0.075)
        let release = smoothingFactor(deltaTime: deltaTime, timeConstant: 0.18)
        engine.pitchRate = smoothed(engine.pitchRate, target.pitchRate, attack: attack, release: release)
        engine.engineGain = smoothed(engine.engineGain, target.engineGain, attack: attack, release: release)
        engine.tireGain = smoothed(engine.tireGain, target.tireGain, attack: attack, release: release)
        engine.ambienceGain = smoothed(engine.ambienceGain, target.ambienceGain, attack: attack, release: release)
    }

    func musicSectionGain() -> Double {
        switch musicSection {
        case .menu: 0.62
        case .countdown: 0.72
        case .racing: 0.82
        case .intense: 0.94
        case .finish: 0.78
        case .failure: 0.5
        }
    }

    private func smoothingFactor(deltaTime: TimeInterval, timeConstant: TimeInterval) -> Double {
        guard deltaTime > 0 else { return 0 }
        return 1 - exp(-min(deltaTime, 0.25) / timeConstant)
    }

    private func smoothed(
        _ current: Double,
        _ target: Double,
        attack: Double,
        release: Double
    ) -> Double {
        current + (target - current) * (target > current ? attack : release)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
