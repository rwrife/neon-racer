import SceneKit
import SpriteKit
import UIKit

enum NeonEffectEvent {
    case collision(intensity: Double), nearMiss, overtake, checkpoint, boostStart, boostEnd, finish, crash
}

struct NeonEffects3DScaling: Equatable, Sendable {
    var quality: CosmeticQualityTier
    var reduceMotion: Bool
    var reduceFlashing: Bool
    var globalIntensity: Double

    func effectiveIntensity(for effect: NeonEffect, configuration: NeonEffectsConfiguration = .standard) -> Double {
        let setting = configuration[effect]
        guard setting.isEnabled else { return 0 }
        var value = setting.intensity * qualityMultiplier(for: effect) * globalIntensity.clamped(to: 0...1)
        if reduceMotion {
            switch effect {
            case .chromaticSeparation, .heatHaze, .speedStreaks, .boostTrails:
                value *= 0.12
            case .sparks, .tireSmoke, .exhaust:
                value *= 0.35
            default:
                break
            }
        }
        if reduceFlashing {
            switch effect {
            case .bloom, .chromaticSeparation, .colorGrade:
                value *= 0.35
            case .collisionFlash:
                value = 0
            default:
                break
            }
        }
        return value.clamped(to: 0...1)
    }

    func qualityMultiplier(for effect: NeonEffect) -> Double {
        switch quality {
        case .efficiency:
            switch effect {
            case .scanlines, .heatHaze, .chromaticSeparation:
                0
            case .speedStreaks, .boostTrails, .sparks, .tireSmoke, .exhaust:
                0.35
            case .bloom, .vignette, .colorGrade, .collisionFlash:
                0.55
            }
        case .balanced:
            switch effect {
            case .heatHaze, .chromaticSeparation:
                0.65
            case .scanlines, .sparks, .tireSmoke:
                0.75
            default:
                0.9
            }
        case .fidelity:
            1
        }
    }
}

private enum NeonEffects3DWeatherMode: Equatable {
    case clear
    case heat
    case rain

    init(id: String) {
        let normalized = id.lowercased()
        if normalized.contains("rain") || normalized.contains("storm") || normalized.contains("wet") {
            self = .rain
        } else if normalized.contains("heat") || normalized.contains("haze") || normalized.contains("coast") || normalized.contains("sun") {
            self = .heat
        } else {
            self = .clear
        }
    }
}

@MainActor
final class NeonEffects3D {
    private weak var camera: SCNCamera?
    private weak var view: SCNView?
    private weak var carNode: SCNNode?
    /// Latest car/camera pose supplied by the race scene; avoids SceneKit scene-lock reads every frame.
    private var carPosition = SCNVector3Zero
    private var cameraForwardY: Double = 0

    func setPose(carPosition: SCNVector3, cameraForward: SCNVector3) {
        self.carPosition = carPosition
        cameraForwardY = Double(cameraForward.y)
    }
    private weak var cameraNode: SCNNode?

    let rootNode = SCNNode()
    private let cameraStreakRoot = SCNNode()
    private var speedStreakSystems: [SCNParticleSystem] = []
    private var boostTrailSystems: [SCNParticleSystem] = []
    private var driftSmokeSystems: [SCNParticleSystem] = []
    private var driftSparkSystems: [SCNParticleSystem] = []
    private var offRoadDustSystem: SCNParticleSystem?
    private var collisionSparkSystem: SCNParticleSystem?
    private var crashSparkSystem: SCNParticleSystem?
    private var nearMissSystem: SCNParticleSystem?
    private var finishBurstSystem: SCNParticleSystem?
    private let collisionEmitter = SCNNode()
    private let crashEmitter = SCNNode()
    private let nearMissEmitter = SCNNode()
    private let finishEmitter = SCNNode()
    private let checkpointRingNode = SCNNode()
    private let overtakePulseNode = SCNNode()
    private let impactShockwaveNode = SCNNode()

    private var overlayScene: SKScene?
    private var flashNode: SKShapeNode?
    private var whooshNodes: [SKShapeNode] = []
    private var glitchBandNodes: [SKShapeNode] = []
    private var lensFlareNodes: [SKShapeNode] = []
    private var rainStreakNodes: [SKShapeNode] = []
    private var heatShimmerNodes: [SKShapeNode] = []

    private var configuration: NeonEffectsConfiguration = .standard
    private var quality: CosmeticQualityTier = .balanced
    private var renderQuality = RenderQualityConfiguration.preset(for: .medium)
    private var weatherMode: NeonEffects3DWeatherMode = .clear
    private var reduceMotion = false
    private var reduceFlashing = false
    private var globalIntensity = 1.0
    private var lastTime: TimeInterval?
    private var randomState: UInt64 = 0xEFFE_C75D_3141_5926
    private var boostRamp = 0.0
    private var collisionEnergy = 0.0
    private var glitchEnergy = 0.0
    private var nearMissEnergy = 0.0
    private var overtakeEnergy = 0.0
    private var checkpointPhase: TimeInterval = 2
    private var finishEnergy = 0.0
    private var flashEnergy = 0.0
    private var fovKickEnergy = 0.0
    private var impactShockwavePhase: TimeInterval = 2
    private var slowMoEnergy = 0.0

    private(set) var cameraShakeOffset = SCNVector3Zero
    private(set) var fovKick: CGFloat = 0
    private(set) var timeDilationHint: Double = 1

    init() {
        rootNode.name = "neon-effects-3d-root"
        cameraStreakRoot.name = "neon-camera-speed-streaks"
        buildEventNodes()
    }

    func configure(camera: SCNCamera) {
        self.camera = camera
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.15
        camera.averageGray = 0.18
        camera.whitePoint = 1.35
        camera.bloomIntensity = 0.85
        camera.bloomThreshold = 0.88
        camera.bloomBlurRadius = 6
        camera.vignettingIntensity = 0.48
        camera.vignettingPower = 0.7
        camera.colorFringeIntensity = 0.18
        camera.colorFringeStrength = 0.45
        camera.motionBlurIntensity = 0
        camera.saturation = 1.26
        camera.contrast = 1.12
    }

    func install(on view: SCNView) {
        self.view = view
        view.backgroundColor = UIColor(red: 0.012, green: 0, blue: 0.045, alpha: 1)
        view.preferredFramesPerSecond = 60
        configureOverlay(for: view)
        refreshTechnique()
    }

    func attach(to scene: SCNScene, carNode: SCNNode, cameraNode: SCNNode) {
        self.carNode = carNode
        self.cameraNode = cameraNode
        rootNode.removeFromParentNode()
        cameraStreakRoot.removeFromParentNode()
        scene.rootNode.addChildNode(rootNode)
        cameraNode.addChildNode(cameraStreakRoot)
        rebuildContinuousEmitters(carNode: carNode)
    }

    func update(speedRatio: Double, isBoosting: Bool, isDrifting: Bool, isOffRoad: Bool, time: TimeInterval) {
        let deltaTime = ((lastTime.map { time - $0 }) ?? (1.0 / 60.0)).clamped(to: 0...(1.0 / 15.0))
        lastTime = time
        let speed = speedRatio.clamped(to: 0...1.35)
        let scaling = currentScaling
        let speedActivation = ((speed - 0.38) / 0.62).clamped(to: 0...1)
        boostRamp += ((isBoosting ? 1 : 0) - boostRamp) * min(1, deltaTime * 7.5)

        collisionEnergy = max(0, collisionEnergy - deltaTime * 3.8)
        glitchEnergy = max(0, glitchEnergy - deltaTime * 4.2)
        nearMissEnergy = max(0, nearMissEnergy - deltaTime * 5.8)
        overtakeEnergy = max(0, overtakeEnergy - deltaTime * 4.5)
        finishEnergy = max(0, finishEnergy - deltaTime * 1.25)
        flashEnergy = max(0, flashEnergy - deltaTime * 4.8)
        fovKickEnergy = max(0, fovKickEnergy - deltaTime * 3.2)
        slowMoEnergy = max(0, slowMoEnergy - deltaTime * 2.9)
        checkpointPhase += deltaTime
        impactShockwavePhase += deltaTime

        updateCamera(speed: speed, speedActivation: speedActivation, scaling: scaling, time: time)
        updateContinuousParticles(speed: speed, speedActivation: speedActivation, isDrifting: isDrifting, isOffRoad: isOffRoad, scaling: scaling)
        updateOverlay(speedActivation: speedActivation, time: time, scaling: scaling)
        updateReusableGeometry(deltaTime: deltaTime)
    }

    func trigger(_ event: NeonEffectEvent) {
        let scaling = currentScaling
        switch event {
        case .collision(let intensity):
            let amount = intensity.clamped(to: 0...1)
            collisionEnergy = max(collisionEnergy, amount)
            glitchEnergy = max(glitchEnergy, amount * 0.52)
            slowMoEnergy = max(slowMoEnergy, amount * 0.58)
            fovKickEnergy = max(fovKickEnergy, amount * 0.82)
            flashEnergy = max(flashEnergy, amount * 0.9)
            startImpactShockwave(relativeToCar: SCNVector3(0, 0.75, 0.15), intensity: amount)
            burst(
                collisionSparkSystem,
                emitter: collisionEmitter,
                relativeToCar: SCNVector3(0, 0.7, 0.2),
                birthRate: 980 * amount * scaling.effectiveIntensity(for: .sparks, configuration: configuration)
            )
        case .nearMiss:
            nearMissEnergy = 1
            fovKickEnergy = max(fovKickEnergy, 0.28)
            burst(nearMissSystem, emitter: nearMissEmitter, relativeToCamera: SCNVector3(0, -0.2, -3.0), birthRate: 460 * scaling.effectiveIntensity(for: .speedStreaks, configuration: configuration))
        case .overtake:
            overtakeEnergy = 1
            fovKickEnergy = max(fovKickEnergy, 0.18)
        case .checkpoint:
            checkpointPhase = 0
            checkpointRingNode.isHidden = false
            checkpointRingNode.position = carPosition
            checkpointRingNode.position.y += 1.1
            fovKickEnergy = max(fovKickEnergy, 0.3)
        case .boostStart:
            boostRamp = max(boostRamp, 0.75)
            fovKickEnergy = max(fovKickEnergy, 0.45)
        case .boostEnd:
            boostRamp = min(boostRamp, 0.35)
        case .finish:
            finishEnergy = 1
            fovKickEnergy = max(fovKickEnergy, 0.65)
            burst(finishBurstSystem, emitter: finishEmitter, relativeToCar: SCNVector3(0, 5.0, -2.5), birthRate: 900 * scaling.effectiveIntensity(for: .sparks, configuration: configuration))
        case .crash:
            collisionEnergy = 1
            glitchEnergy = 1
            flashEnergy = 1
            fovKickEnergy = 1
            slowMoEnergy = 1
            startImpactShockwave(relativeToCar: SCNVector3(0, 0.85, 0), intensity: 1)
            burst(
                collisionSparkSystem,
                emitter: collisionEmitter,
                relativeToCar: SCNVector3(0, 0.75, 0.15),
                birthRate: 1_200 * scaling.effectiveIntensity(for: .sparks, configuration: configuration)
            )
            burst(
                crashSparkSystem,
                emitter: crashEmitter,
                relativeToCar: SCNVector3(0, 0.8, 0),
                birthRate: 1_600 * scaling.effectiveIntensity(for: .sparks, configuration: configuration)
            )
        }
        updateOverlay(speedActivation: 0, time: lastTime ?? 0, scaling: scaling)
    }

    func apply(reduceMotion: Bool, reduceFlashing: Bool, intensity: Double) {
        self.reduceMotion = reduceMotion
        self.reduceFlashing = reduceFlashing
        globalIntensity = intensity.clamped(to: 0...1)
        if reduceMotion {
            cameraShakeOffset = SCNVector3Zero
            fovKick = 0
            timeDilationHint = 1
        }
        refreshTechnique()
    }

    func apply(quality: CosmeticQualityTier) {
        self.quality = quality
        refreshTechnique()
    }

    func apply(renderQuality: RenderQualityConfiguration) {
        self.renderQuality = renderQuality
        camera?.wantsHDR = renderQuality.bloomEnabled
        if !renderQuality.bloomEnabled {
            camera?.bloomIntensity = 0
            camera?.bloomBlurRadius = 0
            camera?.colorFringeIntensity = 0
        }
        refreshTechnique()
    }

    func apply(configuration: NeonEffectsConfiguration) {
        self.configuration = configuration
        refreshTechnique()
    }

    func setWeather(_ id: String) {
        weatherMode = NeonEffects3DWeatherMode(id: id)
    }

    private var currentScaling: NeonEffects3DScaling {
        NeonEffects3DScaling(
            quality: quality,
            reduceMotion: reduceMotion,
            reduceFlashing: reduceFlashing,
            globalIntensity: globalIntensity
        )
    }

    private func buildEventNodes() {
        collisionEmitter.name = "collision-spark-burst"
        crashEmitter.name = "crash-glitch-burst"
        nearMissEmitter.name = "near-miss-whoosh-burst"
        finishEmitter.name = "finish-fireworks-burst"
        rootNode.addChildNode(collisionEmitter)
        rootNode.addChildNode(crashEmitter)
        rootNode.addChildNode(finishEmitter)
        cameraStreakRoot.addChildNode(nearMissEmitter)

        collisionSparkSystem = makeBurstSystem(color: UIColor(red: 1, green: 0.78, blue: 0.18, alpha: 1), size: 0.1, life: 0.58, velocity: 20, spread: 165)
        crashSparkSystem = makeBurstSystem(color: UIColor(red: 1, green: 0.18, blue: 0.84, alpha: 1), size: 0.16, life: 0.86, velocity: 28, spread: 190)
        nearMissSystem = makeStreakSystem(color: UIColor(red: 0, green: 0.96, blue: 1, alpha: 1), warm: false)
        nearMissSystem?.loops = false
        nearMissSystem?.particleLifeSpan = 0.18
        nearMissSystem?.particleVelocity = 36
        finishBurstSystem = makeBurstSystem(color: UIColor(red: 0.28, green: 1, blue: 0.95, alpha: 1), size: 0.12, life: 1.15, velocity: 18, spread: 180)

        if let collisionSparkSystem { collisionEmitter.addParticleSystem(collisionSparkSystem) }
        if let crashSparkSystem { crashEmitter.addParticleSystem(crashSparkSystem) }
        if let nearMissSystem { nearMissEmitter.addParticleSystem(nearMissSystem) }
        if let finishBurstSystem { finishEmitter.addParticleSystem(finishBurstSystem) }

        let ring = SCNTorus(ringRadius: 1.15, pipeRadius: 0.035)
        ring.materials = [Self.material(UIColor(red: 0, green: 0.95, blue: 1, alpha: 1))]
        checkpointRingNode.geometry = ring
        checkpointRingNode.eulerAngles.x = .pi / 2
        checkpointRingNode.isHidden = true
        rootNode.addChildNode(checkpointRingNode)

        // Flat ground ring rather than a sphere so the pulse never swallows the car.
        let pulse = SCNTorus(ringRadius: 1.4, pipeRadius: 0.05)
        pulse.materials = [Self.transparentMaterial(UIColor(red: 1, green: 0.1, blue: 0.58, alpha: 1), alpha: 0.5)]
        overtakePulseNode.geometry = pulse
        overtakePulseNode.isHidden = true
        rootNode.addChildNode(overtakePulseNode)

        let shockwave = SCNTorus(ringRadius: 0.85, pipeRadius: 0.045)
        shockwave.materials = [Self.transparentMaterial(UIColor(red: 1, green: 0.54, blue: 0.08, alpha: 1), alpha: 0.7)]
        impactShockwaveNode.geometry = shockwave
        impactShockwaveNode.eulerAngles.x = .pi / 2
        impactShockwaveNode.isHidden = true
        rootNode.addChildNode(impactShockwaveNode)
    }

    private func rebuildContinuousEmitters(carNode: SCNNode) {
        speedStreakSystems.removeAll(keepingCapacity: true)
        boostTrailSystems.removeAll(keepingCapacity: true)
        driftSmokeSystems.removeAll(keepingCapacity: true)
        driftSparkSystems.removeAll(keepingCapacity: true)
        offRoadDustSystem = nil
        cameraStreakRoot.childNodes.filter { $0.name?.hasPrefix("speed-streak-emitter") == true }.forEach { $0.removeFromParentNode() }
        carNode.childNodes.filter { $0.name?.hasPrefix("neon-effect-emitter") == true }.forEach { $0.removeFromParentNode() }

        for index in 0..<8 {
            let node = SCNNode()
            node.name = "speed-streak-emitter-\(index)"
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let yBand = Float(index / 2) * 0.75 - 0.85
            node.position = SCNVector3(side * (4.6 + Float(index % 4) * 0.35), yBand, -5.8 - Float(index % 3))
            let warm = index % 3 == 0
            let system = makeStreakSystem(
                color: warm ? UIColor(red: 1, green: 0.2, blue: 0.62, alpha: 1) : UIColor(red: 0, green: 0.9, blue: 1, alpha: 1),
                warm: warm
            )
            node.addParticleSystem(system)
            cameraStreakRoot.addChildNode(node)
            speedStreakSystems.append(system)
        }

        for x in [-0.52, 0.52] {
            let node = SCNNode()
            node.name = "neon-effect-emitter-boost-\(x)"
            node.position = SCNVector3(Float(x), 0.45, 2.2)
            let system = makeBoostTrailSystem(warm: x > 0)
            node.addParticleSystem(system)
            carNode.addChildNode(node)
            boostTrailSystems.append(system)
        }

        for x in [-0.82, 0.82] {
            let node = SCNNode()
            node.name = "neon-effect-emitter-drift-\(x)"
            node.position = SCNVector3(Float(x), 0.22, 1.55)
            let smoke = makeSmokeSystem(color: UIColor(white: 0.72, alpha: 0.45), velocity: 1.4)
            let sparks = makeBurstSystem(color: UIColor(red: 1, green: 0.26, blue: 0.74, alpha: 1), size: 0.045, life: 0.28, velocity: 5.5, spread: 82)
            smoke.loops = true
            sparks.loops = true
            node.addParticleSystem(smoke)
            node.addParticleSystem(sparks)
            carNode.addChildNode(node)
            driftSmokeSystems.append(smoke)
            driftSparkSystems.append(sparks)
        }

        let dustNode = SCNNode()
        dustNode.name = "neon-effect-emitter-offroad-dust"
        dustNode.position = SCNVector3(0, 0.18, 1.8)
        let dust = makeSmokeSystem(color: UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 0.48), velocity: 2.4)
        dust.loops = true
        dustNode.addParticleSystem(dust)
        carNode.addChildNode(dustNode)
        offRoadDustSystem = dust
    }

    private func updateCamera(speed: Double, speedActivation: Double, scaling: NeonEffects3DScaling, time: TimeInterval) {
        let bloom = renderQuality.bloomEnabled ? scaling.effectiveIntensity(for: .bloom, configuration: configuration) : 0
        let chromatic = renderQuality.bloomEnabled ? scaling.effectiveIntensity(for: .chromaticSeparation, configuration: configuration) : 0
        let vignette = scaling.effectiveIntensity(for: .vignette, configuration: configuration)
        let colorGrade = scaling.effectiveIntensity(for: .colorGrade, configuration: configuration)
        camera?.bloomIntensity = CGFloat((1.0 + speed * 0.45 + boostRamp * 0.6 + finishEnergy * 0.45 + collisionEnergy * 0.72 + glitchEnergy * 0.55) * bloom)
        camera?.bloomThreshold = CGFloat(0.16 - min(0.08, boostRamp * 0.04 + speedActivation * 0.035))
        camera?.bloomBlurRadius = CGFloat((5.2 + speed * 4.8 + boostRamp * 3.0) * CosmeticQualityConfiguration.preset(for: quality).glowScale)
        camera?.vignettingIntensity = CGFloat((0.34 + speedActivation * 0.2 + collisionEnergy * 0.18 + glitchEnergy * 0.22) * vignette)
        camera?.colorFringeIntensity = CGFloat((0.12 + speedActivation * 0.28 + boostRamp * 0.42 + nearMissEnergy * 0.55 + collisionEnergy * 0.65 + glitchEnergy * 1.45) * chromatic)
        camera?.colorFringeStrength = CGFloat((0.35 + speedActivation * 0.5 + collisionEnergy * 0.8 + glitchEnergy * 1.8) * chromatic)
        camera?.motionBlurIntensity = reduceMotion ? 0 : CGFloat((speedActivation * 0.035 + slowMoEnergy * 0.05) * scaling.effectiveIntensity(for: .speedStreaks, configuration: configuration))
        camera?.saturation = CGFloat(1.04 + 0.26 * colorGrade + boostRamp * 0.05)
        camera?.contrast = CGFloat(1.0 + 0.14 * colorGrade)
        camera?.exposureOffset = CGFloat((finishEnergy * 0.16 + overtakeEnergy * 0.05 + flashEnergy * 0.22 + slowMoEnergy * 0.08) * (reduceFlashing ? 0 : 1))

        if reduceMotion {
            cameraShakeOffset = SCNVector3Zero
        } else {
            let shake = Float((collisionEnergy * 0.72 + glitchEnergy * 0.95) * globalIntensity)
            cameraShakeOffset = SCNVector3(
                sin(Float(time) * 71) * shake * 0.34,
                cos(Float(time) * 89) * shake * 0.2,
                sin(Float(time) * 47) * shake * 0.26
            )
        }
        fovKick = reduceMotion ? 0 : CGFloat((boostRamp * 4.5 + fovKickEnergy * 6.4 + slowMoEnergy * 2.2 + speedActivation * 1.8) * globalIntensity)
        timeDilationHint = reduceMotion ? 1 : (1 - (slowMoEnergy * 0.28 + collisionEnergy * 0.08) * globalIntensity).clamped(to: 0.68...1)
    }

    private func updateContinuousParticles(speed: Double, speedActivation: Double, isDrifting: Bool, isOffRoad: Bool, scaling: NeonEffects3DScaling) {
        let density = CosmeticQualityConfiguration.preset(for: quality).particleDensityScale
        let streakIntensity = scaling.effectiveIntensity(for: .speedStreaks, configuration: configuration)
        for (index, system) in speedStreakSystems.enumerated() {
            let edgeBias = index.isMultiple(of: 2) ? 1.0 : 0.82
            system.birthRate = CGFloat(18 * density * speedActivation * speedActivation * streakIntensity * edgeBias * (1 + boostRamp * 0.9))
            system.particleVelocity = CGFloat(14 + speed * 24 + boostRamp * 18)
            system.particleLifeSpan = CGFloat(0.16 + speedActivation * 0.13)
            system.stretchFactor = CGFloat(0.12 + speedActivation * 0.28 + boostRamp * 0.22)
        }

        let boostIntensity = scaling.effectiveIntensity(for: .boostTrails, configuration: configuration)
        for system in boostTrailSystems {
            system.birthRate = CGFloat((35 + boostRamp * 240) * density * boostIntensity)
            system.particleVelocity = CGFloat(3.4 + boostRamp * 7.5)
            system.particleLifeSpan = CGFloat(0.24 + boostRamp * 0.38)
            system.stretchFactor = CGFloat(0.25 + boostRamp * 1.05)
        }

        let drift = isDrifting ? 1.0 : 0.0
        let offRoad = isOffRoad ? 1.0 : 0.0
        let smokeIntensity = scaling.effectiveIntensity(for: .tireSmoke, configuration: configuration)
        let sparkIntensity = scaling.effectiveIntensity(for: .sparks, configuration: configuration)
        for system in driftSmokeSystems {
            system.birthRate = CGFloat(70 * density * drift * speed * smokeIntensity)
        }
        for system in driftSparkSystems {
            system.birthRate = CGFloat(95 * density * drift * speed * sparkIntensity)
        }
        offRoadDustSystem?.birthRate = CGFloat(95 * density * offRoad * max(0.25, speed) * smokeIntensity)
    }

    private func updateOverlay(speedActivation: Double, time: TimeInterval, scaling: NeonEffects3DScaling) {
        guard let view else { return }
        configureOverlay(for: view)
        let flashIntensity = scaling.effectiveIntensity(for: .collisionFlash, configuration: configuration)
        flashNode?.alpha = reduceFlashing ? 0 : CGFloat(flashEnergy * flashIntensity * 0.46)
        let whoosh = CGFloat((nearMissEnergy * 0.55 + speedActivation * 0.16 + glitchEnergy * 0.35) * scaling.effectiveIntensity(for: .speedStreaks, configuration: configuration))
        for (index, node) in whooshNodes.enumerated() {
            let direction: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let phase = CGFloat((time * (0.9 + Double(index) * 0.07)).truncatingRemainder(dividingBy: 1))
            node.alpha = whoosh * (0.3 + 0.7 * (1 - phase))
            node.xScale = 1 + whoosh * 2.2
            node.position.x = direction * ((overlayScene?.size.width ?? 1) * (0.34 + phase * 0.12))
        }
        updateGlitchBands(time: time, scaling: scaling)
        updateLensFlare(time: time, speedActivation: speedActivation, scaling: scaling)
        updateWeatherOverlay(time: time, speedActivation: speedActivation, scaling: scaling)
    }

    private func updateReusableGeometry(deltaTime: TimeInterval) {
        if checkpointPhase <= 1.05 {
            let progress = CGFloat(checkpointPhase / 1.05)
            checkpointRingNode.opacity = 1 - progress
            let scale = Float(1 + progress * 16)
            checkpointRingNode.scale = SCNVector3(scale, scale, scale)
        } else {
            checkpointRingNode.isHidden = true
        }

        if overtakeEnergy > 0.01, let carNode {
            overtakePulseNode.isHidden = false
            overtakePulseNode.position = carPosition
            overtakePulseNode.position.y += 0.12
            let scale = Float(1 + (1 - overtakeEnergy) * 4)
            overtakePulseNode.scale = SCNVector3(scale, 1, scale)
            overtakePulseNode.opacity = CGFloat(overtakeEnergy * 0.32)
        } else {
            overtakePulseNode.isHidden = true
        }

        if deltaTime > 0, finishEnergy > 0.01 {
            finishEmitter.position.y += Float(sin((lastTime ?? 0) * 2.1) * 0.015)
        }

        if impactShockwavePhase <= 0.72 {
            let progress = CGFloat(impactShockwavePhase / 0.72)
            impactShockwaveNode.isHidden = false
            impactShockwaveNode.opacity = CGFloat((1 - progress) * (reduceFlashing ? 0.32 : 0.82) * globalIntensity)
            let scale = Float(1 + progress * 10)
            impactShockwaveNode.scale = SCNVector3(scale, scale, scale)
        } else {
            impactShockwaveNode.isHidden = true
        }
    }

    private func updateGlitchBands(time: TimeInterval, scaling: NeonEffects3DScaling) {
        let flashScale = reduceFlashing ? 0.28 : 1
        let glitch = CGFloat((glitchEnergy * 0.9 + collisionEnergy * 0.28) * scaling.effectiveIntensity(for: .chromaticSeparation, configuration: configuration) * flashScale)
        for (index, node) in glitchBandNodes.enumerated() {
            guard glitch > 0.002 else {
                node.alpha = 0
                continue
            }
            let direction: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let jitter = CGFloat(random(in: -1...1)) * 18 * glitch
            node.alpha = glitch * CGFloat(0.22 + Double(index % 3) * 0.06)
            node.position.x = (overlayScene?.size.width ?? 0) / 2 + direction * CGFloat(sin(time * 19 + Double(index))) * 20 * glitch + jitter
            node.xScale = 1 + glitch * 1.6
        }
    }

    private func updateLensFlare(time: TimeInterval, speedActivation: Double, scaling: NeonEffects3DScaling) {
        guard quality != .efficiency else {
            lensFlareNodes.forEach { $0.alpha = 0 }
            return
        }
        let forwardY = cameraForwardY
        let horizonAlignment = (1 - abs(forwardY + 0.04) * 5.5).clamped(to: 0...1)
        let sunFacing = weatherMode == .rain ? horizonAlignment * 0.35 : horizonAlignment
        let base = CGFloat(sunFacing * (0.16 + speedActivation * 0.06) * scaling.effectiveIntensity(for: .bloom, configuration: configuration))
        let motionScale: CGFloat = reduceMotion ? 0.65 : 1
        for (index, node) in lensFlareNodes.enumerated() {
            let pulse = 0.86 + 0.14 * sin(time * 0.9 + Double(index))
            node.alpha = base * CGFloat(pulse) * motionScale * CGFloat(1 - Double(index) * 0.08)
        }
    }

    private func updateWeatherOverlay(time: TimeInterval, speedActivation: Double, scaling: NeonEffects3DScaling) {
        let effectScale = scaling.effectiveIntensity(for: .heatHaze, configuration: configuration)
        switch weatherMode {
        case .clear:
            rainStreakNodes.forEach { $0.alpha = 0 }
            heatShimmerNodes.forEach { $0.alpha = 0 }
        case .heat:
            rainStreakNodes.forEach { $0.alpha = 0 }
            let alpha = CGFloat((reduceMotion ? 0.18 : 0.42) * effectScale * (0.45 + speedActivation * 0.35))
            for (index, node) in heatShimmerNodes.enumerated() {
                node.alpha = alpha
                node.position.x = (overlayScene?.size.width ?? 0) / 2 + CGFloat(sin(time * 1.7 + Double(index)) * 24 * Double(effectScale))
            }
        case .rain:
            heatShimmerNodes.forEach { $0.alpha = 0 }
            let streakScale = scaling.effectiveIntensity(for: .speedStreaks, configuration: configuration)
            let alpha = CGFloat((reduceMotion ? 0.12 : 0.32) * streakScale * (0.55 + speedActivation * 0.45))
            let height = overlayScene?.size.height ?? 390
            for (index, node) in rainStreakNodes.enumerated() {
                let phase = CGFloat((time * (reduceMotion ? 0.45 : 1.8) + Double(index) * 0.137).truncatingRemainder(dividingBy: 1))
                node.alpha = alpha * CGFloat(0.7 + Double(index % 3) * 0.1)
                node.position.y = height * (1.15 - phase * 1.35)
            }
        }
    }

    private func startImpactShockwave(relativeToCar offset: SCNVector3, intensity: Double) {
        let position = carPosition
        impactShockwaveNode.position = SCNVector3(position.x + offset.x, position.y + offset.y, position.z + offset.z)
        impactShockwaveNode.scale = SCNVector3(1, 1, 1)
        impactShockwaveNode.opacity = CGFloat(intensity.clamped(to: 0...1))
        impactShockwavePhase = 0
    }

    private func configureOverlay(for view: SCNView) {
        let size = view.bounds.size == .zero ? CGSize(width: 844, height: 390) : view.bounds.size
        if overlayScene?.size == size { return }
        let scene = SKScene(size: size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.isUserInteractionEnabled = false

        let flash = SKShapeNode(rectOf: size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.fillColor = SKColor(red: 1, green: 0.42, blue: 0.16, alpha: 1)
        flash.strokeColor = .clear
        flash.blendMode = .add
        flash.alpha = 0
        scene.addChild(flash)

        whooshNodes.removeAll(keepingCapacity: true)
        for index in 0..<8 {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -size.height * 0.42))
            path.addLine(to: CGPoint(x: 0, y: size.height * 0.42))
            let node = SKShapeNode(path: path)
            node.position = CGPoint(x: size.width / 2, y: size.height / 2)
            node.strokeColor = index.isMultiple(of: 2) ? .cyan : SKColor(red: 1, green: 0.05, blue: 0.56, alpha: 1)
            node.lineWidth = 1.5 + CGFloat(index % 3)
            node.glowWidth = 8
            node.blendMode = .add
            node.zRotation = (index.isMultiple(of: 2) ? -0.18 : 0.18)
            node.alpha = 0
            scene.addChild(node)
            whooshNodes.append(node)
        }

        glitchBandNodes.removeAll(keepingCapacity: true)
        for index in 0..<6 {
            let band = SKShapeNode(rectOf: CGSize(width: size.width * 1.18, height: CGFloat(8 + index * 3)))
            band.position = CGPoint(x: size.width / 2, y: size.height * CGFloat(0.18 + Double(index) * 0.13))
            band.fillColor = index.isMultiple(of: 2) ? SKColor(red: 0, green: 0.95, blue: 1, alpha: 1) : SKColor(red: 1, green: 0.05, blue: 0.58, alpha: 1)
            band.strokeColor = .clear
            band.blendMode = .add
            band.alpha = 0
            scene.addChild(band)
            glitchBandNodes.append(band)
        }

        lensFlareNodes.removeAll(keepingCapacity: true)
        let flareColors = [
            SKColor(red: 1, green: 0.72, blue: 0.2, alpha: 1),
            SKColor(red: 1, green: 0.12, blue: 0.56, alpha: 1),
            SKColor(red: 0, green: 0.92, blue: 1, alpha: 1),
            SKColor(red: 1, green: 0.9, blue: 0.55, alpha: 1)
        ]
        for index in 0..<7 {
            let radius = CGFloat(12 + index * 8)
            let flare = SKShapeNode(circleOfRadius: radius)
            flare.position = CGPoint(
                x: size.width * CGFloat(0.5 + (Double(index) - 2.8) * 0.07),
                y: size.height * CGFloat(0.60 - Double(index) * 0.035)
            )
            flare.fillColor = flareColors[index % flareColors.count].withAlphaComponent(index == 0 ? 0.92 : 0.38)
            flare.strokeColor = flareColors[index % flareColors.count].withAlphaComponent(0.75)
            flare.lineWidth = index == 0 ? 2 : 1
            flare.glowWidth = CGFloat(18 - min(index, 5) * 2)
            flare.blendMode = .add
            flare.alpha = 0
            scene.addChild(flare)
            lensFlareNodes.append(flare)
        }

        rainStreakNodes.removeAll(keepingCapacity: true)
        for index in 0..<28 {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -36))
            path.addLine(to: CGPoint(x: 18, y: 36))
            let streak = SKShapeNode(path: path)
            streak.position = CGPoint(x: size.width * CGFloat((Double((index * 37) % 100) / 100.0)), y: size.height)
            streak.strokeColor = index.isMultiple(of: 3) ? .cyan : SKColor(white: 0.9, alpha: 1)
            streak.lineWidth = 1.1
            streak.glowWidth = 2
            streak.blendMode = .add
            streak.alpha = 0
            scene.addChild(streak)
            rainStreakNodes.append(streak)
        }

        heatShimmerNodes.removeAll(keepingCapacity: true)
        for index in 0..<5 {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -size.width * 0.38, y: 0))
            path.addCurve(
                to: CGPoint(x: size.width * 0.38, y: 0),
                control1: CGPoint(x: -size.width * 0.15, y: CGFloat(12 + index * 3)),
                control2: CGPoint(x: size.width * 0.12, y: CGFloat(-12 - index * 2))
            )
            let shimmer = SKShapeNode(path: path)
            shimmer.position = CGPoint(x: size.width / 2, y: size.height * CGFloat(0.34 + Double(index) * 0.045))
            shimmer.strokeColor = index.isMultiple(of: 2) ? .cyan : SKColor(red: 1, green: 0.12, blue: 0.58, alpha: 1)
            shimmer.lineWidth = 2
            shimmer.glowWidth = 8
            shimmer.blendMode = .add
            shimmer.alpha = 0
            scene.addChild(shimmer)
            heatShimmerNodes.append(shimmer)
        }

        view.overlaySKScene = scene
        overlayScene = scene
        flashNode = flash
    }

    private func refreshTechnique() {
        guard let view else { return }
        view.technique = renderQuality.postProcessingEnabled ? Self.makeTechnique() : nil
    }

    private func burst(_ system: SCNParticleSystem?, emitter: SCNNode, relativeToCar offset: SCNVector3, birthRate: Double) {
        guard let system else { return }
        let position = carPosition
        emitter.position = SCNVector3(position.x + offset.x, position.y + offset.y, position.z + offset.z)
        system.birthRate = CGFloat(birthRate.clamped(to: 0...1_600))
        system.reset()
    }

    private func burst(_ system: SCNParticleSystem?, emitter: SCNNode, relativeToCamera offset: SCNVector3, birthRate: Double) {
        guard let system else { return }
        emitter.position = offset
        system.birthRate = CGFloat(birthRate.clamped(to: 0...1_200))
        system.reset()
    }

    /// Radial soft dot so particles read as glowing sparks instead of squares.
    private static let softDotImage: UIImage = {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.35).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) else { return }
            let center = CGPoint(x: 16, y: 16)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 16, options: [])
        }
    }()

    private func makeStreakSystem(color: UIColor, warm: Bool) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = Self.softDotImage
        system.loops = true
        system.birthRate = 0
        system.birthLocation = .volume
        system.birthDirection = .constant
        system.emittingDirection = SCNVector3(0, 0, 1)
        system.spreadingAngle = 8
        system.particleLifeSpan = 0.22
        system.particleLifeSpanVariation = 0.08
        system.particleVelocity = 22
        system.particleVelocityVariation = 5
        system.particleSize = warm ? 0.08 : 0.065
        system.particleSizeVariation = 0.035
        system.stretchFactor = 0.55
        system.particleColor = color
        system.particleColorVariation = SCNVector4(0.08, 0.04, 0.12, 0.22)
        system.blendMode = .additive
        system.orientationMode = .billboardScreenAligned
        system.sortingMode = .none
        system.isAffectedByGravity = false
        system.emitterShape = SCNBox(width: 0.8, height: 1.2, length: 0.1, chamferRadius: 0)
        return system
    }

    private func makeBoostTrailSystem(warm: Bool) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = Self.softDotImage
        system.loops = true
        system.birthRate = 0
        system.birthLocation = .surface
        system.birthDirection = .constant
        system.emittingDirection = SCNVector3(0, 0.02, 1)
        system.spreadingAngle = 20
        system.particleLifeSpan = 0.35
        system.particleLifeSpanVariation = 0.12
        system.particleVelocity = 5.2
        system.particleVelocityVariation = 1.8
        system.particleSize = 0.15
        system.particleSizeVariation = 0.08
        system.stretchFactor = 0.9
        system.particleColor = warm ? UIColor(red: 1, green: 0.25, blue: 0.08, alpha: 1) : UIColor(red: 0, green: 0.96, blue: 1, alpha: 1)
        system.particleColorVariation = SCNVector4(0.1, 0.08, 0.15, 0.22)
        system.blendMode = .additive
        system.orientationMode = .billboardViewAligned
        system.sortingMode = .none
        system.isAffectedByGravity = false
        system.emitterShape = SCNSphere(radius: 0.16)
        return system
    }

    private func makeSmokeSystem(color: UIColor, velocity: CGFloat) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = Self.softDotImage
        system.loops = true
        system.birthRate = 0
        system.birthLocation = .surface
        system.birthDirection = .constant
        system.emittingDirection = SCNVector3(0, 0.55, 0.75)
        system.spreadingAngle = 48
        system.particleLifeSpan = 0.7
        system.particleLifeSpanVariation = 0.22
        system.particleVelocity = velocity
        system.particleVelocityVariation = velocity * 0.5
        system.particleSize = 0.42
        system.particleSizeVariation = 0.18
        system.particleColor = color
        system.particleColorVariation = SCNVector4(0.08, 0.04, 0.02, 0.28)
        system.blendMode = .alpha
        system.orientationMode = .billboardScreenAligned
        system.sortingMode = .none
        system.isAffectedByGravity = false
        system.emitterShape = SCNSphere(radius: 0.18)
        return system
    }

    private func makeBurstSystem(color: UIColor, size: CGFloat, life: CGFloat, velocity: CGFloat, spread: CGFloat) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = Self.softDotImage
        system.loops = false
        system.birthRate = 0
        system.birthLocation = .surface
        system.birthDirection = .constant
        system.emittingDirection = SCNVector3(0, 0.55, 0.2)
        system.spreadingAngle = spread
        system.particleLifeSpan = life
        system.particleLifeSpanVariation = life * 0.35
        system.particleVelocity = velocity
        system.particleVelocityVariation = velocity * 0.55
        system.particleSize = size
        system.particleSizeVariation = size * 0.7
        system.stretchFactor = 0.35
        system.particleColor = color
        system.particleColorVariation = SCNVector4(0.18, 0.12, 0.2, 0.22)
        system.blendMode = .additive
        system.orientationMode = .billboardScreenAligned
        system.sortingMode = .none
        system.isAffectedByGravity = true
        system.acceleration = SCNVector3(0, -6.5, 0)
        system.emitterShape = SCNSphere(radius: 0.2)
        return system
    }

    private static func makeTechnique() -> SCNTechnique? {
        let dictionary: [String: Any] = [
            "targets": [
                "sceneColor": [
                    "type": "color"
                ]
            ],
            "passes": [
                "scene": [
                    "draw": "DRAW_SCENE",
                    "outputs": [
                        "color": "sceneColor"
                    ]
                ],
                "neonPost": [
                    "draw": "DRAW_QUAD",
                    "inputs": [
                        "colorSampler": "sceneColor"
                    ],
                    "outputs": [
                        "color": "COLOR"
                    ],
                    "metalVertexShader": "neonPostProcessVertex",
                    "metalFragmentShader": "neonPostProcessFragment"
                ]
            ],
            "sequence": ["scene", "neonPost"]
        ]
        return SCNTechnique(dictionary: dictionary)
    }

    private static func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        material.blendMode = .add
        material.isDoubleSided = true
        return material
    }

    private static func transparentMaterial(_ color: UIColor, alpha: CGFloat) -> SCNMaterial {
        let material = material(color)
        material.transparency = alpha
        return material
    }

    private func random(in range: ClosedRange<Double>) -> Double {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1
        let unit = Double(randomState >> 11) / Double(UInt64.max >> 11)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
