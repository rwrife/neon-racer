import SpriteKit

enum NeonEffect: String, CaseIterable, Sendable {
    case bloom
    case scanlines
    case vignette
    case chromaticSeparation
    case colorGrade
    case heatHaze
    case speedStreaks
    case boostTrails
    case sparks
    case tireSmoke
    case exhaust
    case collisionFlash

    var displayName: String {
        switch self {
        case .bloom: "Bloom"
        case .scanlines: "Scanlines"
        case .vignette: "Vignette"
        case .chromaticSeparation: "Chromatic"
        case .colorGrade: "Color grade"
        case .heatHaze: "Heat haze"
        case .speedStreaks: "Speed streaks"
        case .boostTrails: "Boost trails"
        case .sparks: "Sparks"
        case .tireSmoke: "Tire smoke"
        case .exhaust: "Exhaust"
        case .collisionFlash: "Collision flash"
        }
    }
}

struct NeonEffectSetting: Equatable, Sendable {
    var isEnabled: Bool
    var intensity: Double {
        didSet { intensity = intensity.clamped(to: 0...1) }
    }

    init(isEnabled: Bool = true, intensity: Double = 1) {
        self.isEnabled = isEnabled
        self.intensity = intensity.clamped(to: 0...1)
    }
}

struct NeonEffectsConfiguration: Equatable, Sendable {
    private var settings: [NeonEffect: NeonEffectSetting]

    init(settings: [NeonEffect: NeonEffectSetting] = [:]) {
        self.settings = Dictionary(
            uniqueKeysWithValues: NeonEffect.allCases.map {
                ($0, settings[$0] ?? Self.defaultSetting(for: $0))
            }
        )
    }

    subscript(effect: NeonEffect) -> NeonEffectSetting {
        get { settings[effect] ?? Self.defaultSetting(for: effect) }
        set { settings[effect] = newValue }
    }

    static let standard = NeonEffectsConfiguration()

    private static func defaultSetting(for effect: NeonEffect) -> NeonEffectSetting {
        switch effect {
        case .bloom: NeonEffectSetting(intensity: 0.75)
        case .scanlines: NeonEffectSetting(intensity: 0.28)
        case .vignette: NeonEffectSetting(intensity: 0.55)
        case .chromaticSeparation: NeonEffectSetting(intensity: 0.22)
        case .colorGrade: NeonEffectSetting(intensity: 0.18)
        case .heatHaze: NeonEffectSetting(intensity: 0.22)
        case .speedStreaks: NeonEffectSetting(intensity: 0.72)
        case .boostTrails: NeonEffectSetting(intensity: 0.9)
        case .sparks: NeonEffectSetting(intensity: 0.85)
        case .tireSmoke: NeonEffectSetting(intensity: 0.48)
        case .exhaust: NeonEffectSetting(intensity: 0.5)
        case .collisionFlash: NeonEffectSetting(intensity: 0.75)
        }
    }
}

struct NeonEffectsAccessibility: Equatable, Sendable {
    var reduceMotion: Bool
    var reduceFlashes: Bool
}

struct NeonEffectsDrivers: Sendable {
    var normalizedSpeed: Double
    var boost: Double
    var steering: Double
    var offRoad: Double
    var carPosition: CGPoint
    var currentTime: TimeInterval
    var deltaTime: TimeInterval
}

struct NeonEffectsMetrics: Equatable, Sendable {
    let activeEffects: Int
    let activePooledNodes: Int
    let pooledNodeCapacity: Int
}

@MainActor
final class NeonEffectsStack {
    private static let allEffects = NeonEffect.allCases

    @MainActor
    private final class Particle {
        let node: SKShapeNode
        var velocity = CGVector.zero
        var age: TimeInterval = 0
        var lifetime: TimeInterval = 1
        var startScale: CGFloat = 1

        init(node: SKShapeNode) {
            self.node = node
            node.isHidden = true
        }
    }

    private let quality: CosmeticQualityConfiguration
    private let size: CGSize
    private let overlayRoot = SKNode()
    private let motionRoot = SKNode()
    private let scanlineNode = SKShapeNode()
    private let vignetteNode = SKShapeNode()
    private let colorGradeNode: SKShapeNode
    private let collisionFlashNode: SKShapeNode
    private var chromaticNodes: [SKShapeNode] = []
    private var heatHazeNodes: [SKShapeNode] = []
    private var speedStreakNodes: [SKShapeNode] = []
    private var boostTrailPool: [Particle] = []
    private var sparkPool: [Particle] = []
    private var smokePool: [Particle] = []
    private var exhaustPool: [Particle] = []
    private var boostTrailCursor = 0
    private var sparkCursor = 0
    private var smokeCursor = 0
    private var exhaustCursor = 0
    private var boostEmissionRemainder = 0.0
    private var sparkEmissionRemainder = 0.0
    private var smokeEmissionRemainder = 0.0
    private var exhaustEmissionRemainder = 0.0
    private var collisionEnergy = 0.0
    private var lastCarPosition = CGPoint.zero
    private var randomState: UInt64 = 0xBADC_0FFE_E0DD_F00D
    private(set) var configuration: NeonEffectsConfiguration
    private var accessibility = NeonEffectsAccessibility(
        reduceMotion: false,
        reduceFlashes: false
    )

#if DEBUG
    private let debugRoot = SKNode()
    private var debugLabels: [NeonEffect: SKLabelNode] = [:]
#endif

    init(
        sceneSize: CGSize,
        quality: CosmeticQualityConfiguration,
        configuration: NeonEffectsConfiguration = .standard
    ) {
        self.size = sceneSize
        self.quality = quality
        self.configuration = configuration
        colorGradeNode = SKShapeNode(
            rectOf: sceneSize,
            cornerRadius: 0
        )
        collisionFlashNode = SKShapeNode(
            rectOf: sceneSize,
            cornerRadius: 0
        )
        buildNodes()
    }

    func install(in scene: SKScene, hudRoot: SKNode) {
        overlayRoot.zPosition = 80
        motionRoot.zPosition = 30
        scene.addChild(motionRoot)
        scene.addChild(overlayRoot)
#if DEBUG
        buildDebugPanel(in: hudRoot)
#endif
    }

    func apply(
        configuration: NeonEffectsConfiguration,
        accessibility: NeonEffectsAccessibility
    ) {
        self.configuration = configuration
        self.accessibility = accessibility
        refreshStaticEffects()
#if DEBUG
        refreshDebugPanel()
#endif
    }

    func setting(for effect: NeonEffect) -> NeonEffectSetting {
        configuration[effect]
    }

    func effectiveIntensity(for effect: NeonEffect) -> Double {
        let setting = configuration[effect]
        guard setting.isEnabled else { return 0 }

        var intensity = setting.intensity * qualityMultiplier(for: effect)
        if accessibility.reduceMotion {
            switch effect {
            case .heatHaze, .speedStreaks, .boostTrails, .sparks, .tireSmoke, .exhaust:
                intensity *= 0.18
            default:
                break
            }
        }
        if accessibility.reduceFlashes {
            switch effect {
            case .bloom, .chromaticSeparation, .colorGrade:
                intensity *= 0.35
            case .collisionFlash:
                intensity *= 0.12
            default:
                break
            }
        }
        return intensity.clamped(to: 0...1)
    }

    func update(_ drivers: NeonEffectsDrivers) {
        lastCarPosition = drivers.carPosition
        let deltaTime = drivers.deltaTime.clamped(to: 0...(1.0 / 15.0))
        let speed = drivers.normalizedSpeed.clamped(to: 0...1.25)
        let boost = drivers.boost.clamped(to: 0...1)
        let motionSpeed = accessibility.reduceMotion ? min(speed, 0.35) : speed

        updateStaticOverlays(speed: speed, currentTime: drivers.currentTime)
        updateSpeedStreaks(speed: motionSpeed, currentTime: drivers.currentTime)
        updateEmitters(
            drivers: drivers,
            speed: motionSpeed,
            boost: boost,
            deltaTime: deltaTime
        )
        update(pool: boostTrailPool, deltaTime: deltaTime)
        update(pool: sparkPool, deltaTime: deltaTime)
        update(pool: smokePool, deltaTime: deltaTime)
        update(pool: exhaustPool, deltaTime: deltaTime)

        collisionEnergy = max(0, collisionEnergy - deltaTime * 3.8)
        collisionFlashNode.alpha = CGFloat(
            collisionEnergy * effectiveIntensity(for: .collisionFlash) * 0.55
        )
        collisionFlashNode.isHidden = collisionFlashNode.alpha <= 0.001
    }

    func triggerCollision(intensity: Double) {
        guard effectiveIntensity(for: .collisionFlash) > 0 else { return }
        collisionEnergy = max(collisionEnergy, intensity.clamped(to: 0...1))
        let sparkIntensity = effectiveIntensity(for: .sparks)
        emitSparks(
            count: Int(14 * sparkIntensity),
            origin: lastCarPosition,
            inheritedVelocity: .zero
        )
    }

    var metrics: NeonEffectsMetrics {
        let activePooledNodes = activeCount(in: boostTrailPool)
            + activeCount(in: sparkPool)
            + activeCount(in: smokePool)
            + activeCount(in: exhaustPool)
        return NeonEffectsMetrics(
            activeEffects: Self.allEffects.reduce(0) {
                $0 + (effectiveIntensity(for: $1) > 0 ? 1 : 0)
            },
            activePooledNodes: activePooledNodes,
            pooledNodeCapacity: boostTrailPool.count
                + sparkPool.count
                + smokePool.count
                + exhaustPool.count
        )
    }

#if DEBUG
    func toggleDebugEffect(at scenePoint: CGPoint) -> Bool {
        guard let scene = debugRoot.scene else { return false }
        let localPoint = debugRoot.convert(scenePoint, from: scene)
        for effect in NeonEffect.allCases {
            guard let label = debugLabels[effect] else { continue }
            if label.calculateAccumulatedFrame().insetBy(dx: -8, dy: -5).contains(localPoint) {
                var setting = configuration[effect]
                setting.isEnabled.toggle()
                configuration[effect] = setting
                refreshStaticEffects()
                refreshDebugPanel()
                return true
            }
        }
        return false
    }
#endif

    private func buildNodes() {
        scanlineNode.path = makeScanlinePath()
        scanlineNode.strokeColor = .black
        scanlineNode.lineWidth = 2
        scanlineNode.zPosition = 10
        overlayRoot.addChild(scanlineNode)

        vignetteNode.path = CGPath(
            roundedRect: CGRect(
                x: -size.width / 2 + 12,
                y: -size.height / 2 + 12,
                width: size.width - 24,
                height: size.height - 24
            ),
            cornerWidth: 110,
            cornerHeight: 110,
            transform: nil
        )
        vignetteNode.strokeColor = .black
        vignetteNode.lineWidth = 90
        vignetteNode.zPosition = 20
        overlayRoot.addChild(vignetteNode)

        colorGradeNode.fillColor = SKColor(red: 0.18, green: 0.02, blue: 0.34, alpha: 1)
        colorGradeNode.strokeColor = .clear
        colorGradeNode.blendMode = .add
        colorGradeNode.zPosition = 5
        overlayRoot.addChild(colorGradeNode)

        collisionFlashNode.fillColor = SKColor(red: 1, green: 0.45, blue: 0.16, alpha: 1)
        collisionFlashNode.strokeColor = .clear
        collisionFlashNode.blendMode = .add
        collisionFlashNode.zPosition = 30
        collisionFlashNode.isHidden = true
        overlayRoot.addChild(collisionFlashNode)

        buildChromaticEdges()
        buildHeatHaze()
        buildSpeedStreaks()
        buildParticlePools()
        refreshStaticEffects()
    }

    private func buildChromaticEdges() {
        let colors = [
            SKColor(red: 0, green: 0.9, blue: 1, alpha: 1),
            SKColor(red: 1, green: 0.05, blue: 0.5, alpha: 1)
        ]
        for (index, color) in colors.enumerated() {
            let inset = CGFloat(24 + index * 12)
            let node = SKShapeNode(
                rect: CGRect(
                    x: -size.width / 2 + inset,
                    y: -size.height / 2 + inset,
                    width: size.width - inset * 2,
                    height: size.height - inset * 2
                ),
                cornerRadius: 90
            )
            node.strokeColor = color
            node.fillColor = .clear
            node.lineWidth = 4
            node.blendMode = .add
            node.zPosition = 15
            overlayRoot.addChild(node)
            chromaticNodes.append(node)
        }
    }

    private func buildHeatHaze() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -230, y: 0))
        path.addCurve(
            to: CGPoint(x: 230, y: 0),
            control1: CGPoint(x: -100, y: 16),
            control2: CGPoint(x: 100, y: -16)
        )
        let count = quality.tier == .fidelity ? 5 : 3
        for index in 0..<count {
            let node = SKShapeNode(path: path)
            node.strokeColor = SKColor(red: 1, green: 0.18, blue: 0.55, alpha: 1)
            node.lineWidth = 3
            node.glowWidth = 5 * CGFloat(quality.glowScale)
            node.blendMode = .add
            node.position.y = -205 + CGFloat(index * 20)
            motionRoot.addChild(node)
            heatHazeNodes.append(node)
        }
    }

    private func buildSpeedStreaks() {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: -150))
        let count: Int
        switch quality.tier {
        case .efficiency: count = 8
        case .balanced: count = 16
        case .fidelity: count = 26
        }
        for index in 0..<count {
            let node = SKShapeNode(path: path)
            node.strokeColor = index.isMultiple(of: 2)
                ? SKColor(red: 0, green: 0.9, blue: 1, alpha: 1)
                : SKColor(red: 1, green: 0.08, blue: 0.52, alpha: 1)
            node.lineWidth = 3
            node.glowWidth = 4 * CGFloat(quality.glowScale)
            node.blendMode = .add
            node.zRotation = index.isMultiple(of: 2) ? -0.18 : 0.18
            motionRoot.addChild(node)
            speedStreakNodes.append(node)
        }
    }

    private func buildParticlePools() {
        boostTrailPool = makePool(
            count: scaledPoolCount(24),
            radius: 8,
            color: SKColor(red: 0, green: 0.9, blue: 1, alpha: 1),
            blendMode: .add
        )
        sparkPool = makePool(
            count: scaledPoolCount(28),
            radius: 4,
            color: SKColor(red: 1, green: 0.7, blue: 0.12, alpha: 1),
            blendMode: .add
        )
        smokePool = makePool(
            count: scaledPoolCount(20),
            radius: 14,
            color: SKColor(white: 0.7, alpha: 1),
            blendMode: .alpha
        )
        exhaustPool = makePool(
            count: scaledPoolCount(16),
            radius: 6,
            color: SKColor(red: 1, green: 0.18, blue: 0.5, alpha: 1),
            blendMode: .add
        )
    }

    private func makePool(
        count: Int,
        radius: CGFloat,
        color: SKColor,
        blendMode: SKBlendMode
    ) -> [Particle] {
        (0..<count).map { _ in
            let node = SKShapeNode(circleOfRadius: radius)
            node.fillColor = color
            node.strokeColor = .clear
            node.blendMode = blendMode
            motionRoot.addChild(node)
            return Particle(node: node)
        }
    }

    private func scaledPoolCount(_ base: Int) -> Int {
        max(2, Int(Double(base) * quality.particleDensityScale))
    }

    private func refreshStaticEffects() {
        scanlineNode.isHidden = effectiveIntensity(for: .scanlines) <= 0
        vignetteNode.isHidden = effectiveIntensity(for: .vignette) <= 0
        colorGradeNode.isHidden = effectiveIntensity(for: .colorGrade) <= 0
        for node in chromaticNodes {
            node.isHidden = effectiveIntensity(for: .chromaticSeparation) <= 0
        }
        for node in heatHazeNodes {
            node.isHidden = effectiveIntensity(for: .heatHaze) <= 0
        }
    }

    private func updateStaticOverlays(speed: Double, currentTime: TimeInterval) {
        scanlineNode.alpha = CGFloat(effectiveIntensity(for: .scanlines) * 0.24)
        vignetteNode.alpha = CGFloat(effectiveIntensity(for: .vignette) * 0.72)
        colorGradeNode.alpha = CGFloat(effectiveIntensity(for: .colorGrade) * 0.13)

        let chromatic = effectiveIntensity(for: .chromaticSeparation)
        for (index, node) in chromaticNodes.enumerated() {
            node.alpha = CGFloat(chromatic * (0.08 + speed * 0.12))
            node.position.x = CGFloat((index == 0 ? -1 : 1) * (2 + speed * 5))
        }

        let haze = effectiveIntensity(for: .heatHaze) * max(0, speed - 0.25)
        for (index, node) in heatHazeNodes.enumerated() {
            node.alpha = CGFloat(haze * 0.32)
            node.position.x = CGFloat(sin(currentTime * 2.4 + Double(index)) * 14 * haze)
        }
    }

    private func updateSpeedStreaks(speed: Double, currentTime: TimeInterval) {
        let effectIntensity = effectiveIntensity(for: .speedStreaks)
        let activation = ((speed - 0.42) / 0.58).clamped(to: 0...1) * effectIntensity
        let halfWidth = size.width / 2
        let height = size.height
        for (index, node) in speedStreakNodes.enumerated() {
            guard activation > 0.001 else {
                node.isHidden = true
                continue
            }
            let seed = Double(index) * 0.618_033_988_75
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let x = side * (halfWidth * CGFloat(0.45 + (seed.truncatingRemainder(dividingBy: 0.5))))
            let cycle = (currentTime * (0.7 + speed * 1.8) + seed)
                .truncatingRemainder(dividingBy: 1)
            node.position = CGPoint(x: x, y: height / 2 - CGFloat(cycle) * height * 1.25)
            node.yScale = CGFloat(0.45 + speed * 1.1)
            node.alpha = CGFloat(activation * (0.16 + seed.truncatingRemainder(dividingBy: 0.18)))
            node.isHidden = false
        }
    }

    private func updateEmitters(
        drivers: NeonEffectsDrivers,
        speed: Double,
        boost: Double,
        deltaTime: TimeInterval
    ) {
        let boostRate = 30 * speed * boost * effectiveIntensity(for: .boostTrails)
        boostEmissionRemainder += boostRate * deltaTime
        while boostEmissionRemainder >= 1 {
            boostEmissionRemainder -= 1
            emitBoostTrail(origin: drivers.carPosition)
        }

        let smokeRate = 14
            * max(abs(drivers.steering) - 0.35, drivers.offRoad)
            * speed
            * effectiveIntensity(for: .tireSmoke)
        smokeEmissionRemainder += smokeRate * deltaTime
        while smokeEmissionRemainder >= 1 {
            smokeEmissionRemainder -= 1
            emitSmoke(origin: drivers.carPosition)
        }

        let exhaustRate = (4 + speed * 10)
            * effectiveIntensity(for: .exhaust)
        exhaustEmissionRemainder += exhaustRate * deltaTime
        while exhaustEmissionRemainder >= 1 {
            exhaustEmissionRemainder -= 1
            emitExhaust(origin: drivers.carPosition, boost: boost)
        }

        let sparkRate = drivers.offRoad * speed * 18 * effectiveIntensity(for: .sparks)
        sparkEmissionRemainder += sparkRate * deltaTime
        if sparkEmissionRemainder >= 1 {
            let count = Int(sparkEmissionRemainder)
            sparkEmissionRemainder -= Double(count)
            emitSparks(
                count: count,
                origin: drivers.carPosition,
                inheritedVelocity: CGVector(dx: 0, dy: -80 * speed)
            )
        }
    }

    private func emitBoostTrail(origin: CGPoint) {
        guard !boostTrailPool.isEmpty else { return }
        let particle = boostTrailPool[boostTrailCursor]
        boostTrailCursor = (boostTrailCursor + 1) % boostTrailPool.count
        activate(
            particle,
            position: CGPoint(x: origin.x + random(in: -105...105), y: origin.y - 80),
            velocity: CGVector(dx: random(in: -18...18), dy: random(in: -250 ... -170)),
            lifetime: 0.42,
            scale: 0.7
        )
    }

    private func emitSmoke(origin: CGPoint) {
        guard !smokePool.isEmpty else { return }
        let particle = smokePool[smokeCursor]
        smokeCursor = (smokeCursor + 1) % smokePool.count
        activate(
            particle,
            position: CGPoint(x: origin.x + random(in: -125...125), y: origin.y - 70),
            velocity: CGVector(dx: random(in: -35...35), dy: random(in: -75 ... -30)),
            lifetime: 0.75,
            scale: 0.55
        )
    }

    private func emitExhaust(origin: CGPoint, boost: Double) {
        guard !exhaustPool.isEmpty else { return }
        let particle = exhaustPool[exhaustCursor]
        exhaustCursor = (exhaustCursor + 1) % exhaustPool.count
        activate(
            particle,
            position: CGPoint(x: origin.x + random(in: -30...30), y: origin.y - 80),
            velocity: CGVector(dx: random(in: -12...12), dy: -90 - 100 * boost),
            lifetime: 0.3,
            scale: CGFloat(0.45 + boost * 0.35)
        )
    }

    private func emitSparks(
        count: Int,
        origin: CGPoint,
        inheritedVelocity: CGVector
    ) {
        guard !sparkPool.isEmpty else { return }
        for _ in 0..<min(count, sparkPool.count) {
            let particle = sparkPool[sparkCursor]
            sparkCursor = (sparkCursor + 1) % sparkPool.count
            activate(
                particle,
                position: CGPoint(x: origin.x + random(in: -80...80), y: origin.y - 40),
                velocity: CGVector(
                    dx: inheritedVelocity.dx + random(in: -260...260),
                    dy: inheritedVelocity.dy + random(in: 80...320)
                ),
                lifetime: 0.45,
                scale: CGFloat(random(in: 0.55...1.2))
            )
        }
    }

    private func activate(
        _ particle: Particle,
        position: CGPoint,
        velocity: CGVector,
        lifetime: TimeInterval,
        scale: CGFloat
    ) {
        particle.node.position = position
        particle.node.alpha = 1
        particle.node.setScale(scale)
        particle.node.isHidden = false
        particle.velocity = velocity
        particle.age = 0
        particle.lifetime = lifetime
        particle.startScale = scale
    }

    private func update(pool: [Particle], deltaTime: TimeInterval) {
        for particle in pool where !particle.node.isHidden {
            particle.age += deltaTime
            if particle.age >= particle.lifetime {
                particle.node.isHidden = true
                continue
            }

            particle.node.position.x += particle.velocity.dx * deltaTime
            particle.node.position.y += particle.velocity.dy * deltaTime
            particle.velocity.dy -= 120 * deltaTime
            let progress = particle.age / particle.lifetime
            particle.node.alpha = CGFloat(1 - progress)
            particle.node.setScale(particle.startScale * CGFloat(1 + progress * 0.45))
        }
    }

    private func activeCount(in pool: [Particle]) -> Int {
        pool.reduce(0) { $0 + ($1.node.isHidden ? 0 : 1) }
    }

    private func makeScanlinePath() -> CGPath {
        let path = CGMutablePath()
        var y = -size.height / 2
        while y <= size.height / 2 {
            path.move(to: CGPoint(x: -size.width / 2, y: y))
            path.addLine(to: CGPoint(x: size.width / 2, y: y))
            y += 9
        }
        return path
    }

    private func qualityMultiplier(for effect: NeonEffect) -> Double {
        switch quality.tier {
        case .efficiency:
            switch effect {
            case .heatHaze, .chromaticSeparation, .sparks: 0
            case .speedStreaks, .boostTrails, .tireSmoke: 0.45
            case .bloom, .scanlines, .vignette, .colorGrade, .exhaust, .collisionFlash: 0.65
            }
        case .balanced:
            switch effect {
            case .heatHaze: 0.55
            case .chromaticSeparation, .sparks, .tireSmoke: 0.75
            default: 0.9
            }
        case .fidelity:
            1
        }
    }

    private func random(in range: ClosedRange<Double>) -> CGFloat {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1
        let unit = Double(randomState >> 11) / Double(UInt64.max >> 11)
        return CGFloat(range.lowerBound + (range.upperBound - range.lowerBound) * unit)
    }

#if DEBUG
    private func buildDebugPanel(in hudRoot: SKNode) {
        debugRoot.position = CGPoint(x: -size.width / 2 + 28, y: size.height / 2 - 122)
        debugRoot.zPosition = 1_100
        hudRoot.addChild(debugRoot)

        for (index, effect) in NeonEffect.allCases.enumerated() {
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.name = "debug-effect-\(effect.rawValue)"
            label.fontSize = 18
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .center
            label.position.y = CGFloat(index) * -25
            debugRoot.addChild(label)
            debugLabels[effect] = label
        }
        refreshDebugPanel()
    }

    private func refreshDebugPanel() {
        for effect in NeonEffect.allCases {
            let enabled = configuration[effect].isEnabled
            let qualityAllowsEffect = qualityMultiplier(for: effect) > 0
            debugLabels[effect]?.text = "\(enabled ? "●" : "○") \(effect.displayName)"
            debugLabels[effect]?.fontColor = !qualityAllowsEffect
                ? .gray
                : (enabled ? .green : .white)
        }
    }
#endif
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
