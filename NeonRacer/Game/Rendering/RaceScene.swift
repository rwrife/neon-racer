import SpriteKit

final class RaceScene: SKScene {
    var audioFrameHandler: ((EngineAudioInput, TimeInterval) -> Void)?
    var audioEventHandler: ((AudioEvent) -> Void)?
    var commandProvider: @MainActor () -> PlayerCommand = { .idle }
    var engineIntensityDidChange: @MainActor (Double) -> Void = { _ in }
    var feedbackDidOccur: @MainActor (HapticEvent) -> Void = { _ in }

    private var simulation = RaceSimulation()
    private let quality: CosmeticQualityConfiguration
    private var previousUpdateTime: TimeInterval?
    private let carNode = SKShapeNode()
    private let speedLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let roadNode = SKNode()
    private var previousPhase = RacePhase.ready
    private var wasBoostActive = false
    private let centerCueNode = SKShapeNode()
    private var accessibilitySettings = AccessibilitySettings.defaults
    private var systemReduceMotion = false
#if DEBUG
    private let performanceMetrics = DebugPerformanceMetrics()
    private let performanceLabel = SKLabelNode(fontNamed: "Menlo")
#endif

    func apply(settings: AccessibilitySettings, systemReduceMotion: Bool) {
        accessibilitySettings = settings
        self.systemReduceMotion = systemReduceMotion
        applyPalette()
    }

    override convenience init() {
        self.init(
            size: CGSize(width: 1920, height: 1080),
            quality: .environmentDefault
        )
    }

    init(size: CGSize, quality: CosmeticQualityConfiguration) {
        self.quality = quality
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.015, green: 0.005, blue: 0.06, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        quality = .balanced
        super.init(coder: aDecoder)
    }

    override func didMove(to view: SKView) {
        guard children.isEmpty else {
            return
        }

        view.preferredFramesPerSecond = 120
        view.contentScaleFactor *= CGFloat(quality.renderTargetScale)
        buildHorizon()
        buildRoadGrid()
        buildCar()
        buildHUD()
        applyPalette()
    }

    override func update(_ currentTime: TimeInterval) {
        let frameInterval = PerformanceInstrumentation.begin(.frame)
        defer { PerformanceInstrumentation.end(.frame, frameInterval) }

        let frameDelta = previousUpdateTime.map { currentTime - $0 } ?? 0
        previousUpdateTime = currentTime

        let command = commandProvider()
        simulation.advance(
            frameDelta: frameDelta,
            command: command
        )
        let isBoostActive = simulation.state.isBoostActive
        if isBoostActive && !wasBoostActive {
            feedbackDidOccur(.boost)
        }
        wasBoostActive = isBoostActive

        render(snapshot: simulation.renderSnapshot, currentTime: currentTime)
        updateAudio(command: command, deltaTime: frameDelta)
        engineIntensityDidChange(
            simulation.state.speed / RaceConfiguration.standard.maximumSpeed
        )

#if DEBUG
        performanceLabel.text = performanceMetrics.record(
            frameDelta: frameDelta,
            activeVehicles: 1,
            segmentCount: 14,
            nodeCount: nodeCountIncludingDescendants,
            qualityTier: quality.tier
        ).overlayText
#endif
    }

    func pauseForInterruption() {
        simulation.setPaused(true)
        previousUpdateTime = nil
        isPaused = true
        engineIntensityDidChange(0)
    }

    func resumeAfterInterruption() {
        previousUpdateTime = nil
        simulation.setPaused(false)
        isPaused = false
    }

    func tearDown() {
        pauseForInterruption()
        wasBoostActive = false
        commandProvider = { .idle }
        feedbackDidOccur = { _ in }
        engineIntensityDidChange = { _ in }
    }

    private func updateAudio(command: PlayerCommand, deltaTime: TimeInterval) {
        let state = simulation.state
        let normalizedSpeed = state.speed / RaceConfiguration.standard.maximumSpeed
        audioFrameHandler?(
            EngineAudioInput(
                normalizedRPM: normalizedSpeed,
                normalizedSpeed: normalizedSpeed,
                throttle: command.throttle,
                drift: abs(command.steering) * normalizedSpeed,
                boost: state.isBoostActive ? 1 : 0,
                offRoad: max(0, abs(state.lateralPosition) - 0.82) / 0.18,
                collisionRecovery: 0
            ),
            deltaTime
        )

        if state.phase != previousPhase {
            switch state.phase {
            case .running where previousPhase == .paused:
                audioEventHandler?(.raceResumed)
            case .paused:
                audioEventHandler?(.racePaused)
            case .finished:
                audioEventHandler?(.finish)
            case .failed:
                audioEventHandler?(.failure)
            case .ready, .running:
                break
            }
            previousPhase = state.phase
        }
    }

    private func buildHorizon() {
        let sun = SKShapeNode(circleOfRadius: 175)
        sun.fillColor = SKColor(red: 1, green: 0.18, blue: 0.48, alpha: 1)
        sun.strokeColor = SKColor(red: 1, green: 0.74, blue: 0.18, alpha: 1)
        sun.lineWidth = 8
        sun.glowWidth = 28 * CGFloat(quality.glowScale)
        sun.position = CGPoint(x: 0, y: 180)
        sun.zPosition = -20
        addChild(sun)

        let skyline = SKShapeNode(path: skylinePath())
        skyline.fillColor = SKColor(red: 0.03, green: 0.01, blue: 0.11, alpha: 1)
        skyline.strokeColor = SKColor(red: 0.88, green: 0.08, blue: 1, alpha: 1)
        skyline.lineWidth = 5
        skyline.glowWidth = 10 * CGFloat(quality.glowScale)
        skyline.zPosition = -10
        addChild(skyline)
    }

    private func buildRoadGrid() {
        roadNode.zPosition = 0
        addChild(roadNode)

        let road = CGMutablePath()
        road.move(to: CGPoint(x: -80, y: 40))
        road.addLine(to: CGPoint(x: -900, y: -540))
        road.move(to: CGPoint(x: 80, y: 40))
        road.addLine(to: CGPoint(x: 900, y: -540))

        for lane in -4...4 {
            let horizonX = CGFloat(lane) * 18
            let foregroundX = CGFloat(lane) * 180
            road.move(to: CGPoint(x: horizonX, y: 40))
            road.addLine(to: CGPoint(x: foregroundX, y: -540))
        }

        for index in 0..<14 {
            let progress = CGFloat(index) / 13
            let eased = progress * progress
            let y = 40 - eased * 580
            let halfWidth = 80 + eased * 820
            road.move(to: CGPoint(x: -halfWidth, y: y))
            road.addLine(to: CGPoint(x: halfWidth, y: y))
        }

        let grid = SKShapeNode(path: road)
        grid.name = "road-grid"
        grid.lineWidth = 3
        grid.glowWidth = 8 * CGFloat(quality.glowScale)
        roadNode.addChild(grid)

        let centerCue = CGMutablePath()
        for y in stride(from: CGFloat(20), through: -520, by: -55) {
            centerCue.move(to: CGPoint(x: 0, y: y))
            centerCue.addLine(to: CGPoint(x: 0, y: y - 28))
        }
        centerCueNode.path = centerCue
        centerCueNode.lineWidth = 9
        roadNode.addChild(centerCueNode)
    }

    private func buildCar() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -170, y: -80))
        path.addLine(to: CGPoint(x: -125, y: 70))
        path.addLine(to: CGPoint(x: -70, y: 125))
        path.addLine(to: CGPoint(x: 70, y: 125))
        path.addLine(to: CGPoint(x: 125, y: 70))
        path.addLine(to: CGPoint(x: 170, y: -80))
        path.closeSubpath()

        carNode.path = path
        carNode.lineWidth = 8
        carNode.glowWidth = 18 * CGFloat(quality.glowScale)
        carNode.position = CGPoint(x: 0, y: -330)
        carNode.zPosition = 20
        addChild(carNode)
    }

    private func buildHUD() {
        speedLabel.horizontalAlignmentMode = .right
        speedLabel.verticalAlignmentMode = .top
        speedLabel.position = CGPoint(x: 890, y: 490)
        speedLabel.zPosition = 100
        addChild(speedLabel)

#if DEBUG
        performanceLabel.fontSize = 22
        performanceLabel.fontColor = .white
        performanceLabel.numberOfLines = 3
        performanceLabel.horizontalAlignmentMode = .left
        performanceLabel.verticalAlignmentMode = .top
        performanceLabel.position = CGPoint(x: -930, y: 500)
        performanceLabel.zPosition = 100
        addChild(performanceLabel)
#endif
    }

    private func render(snapshot: RaceRenderSnapshot, currentTime: TimeInterval) {
        let roadInterval = PerformanceInstrumentation.begin(.roadProjection)
        let alpha = CGFloat(snapshot.interpolationAlpha)
        let interpolatedLateral = CGFloat(snapshot.previous.lateralPosition) * (1 - alpha)
            + CGFloat(snapshot.current.lateralPosition) * alpha
        let interpolatedDistance = snapshot.previous.distance * (1 - Double(alpha))
            + snapshot.current.distance * Double(alpha)
        let state = snapshot.current

        carNode.position.x = interpolatedLateral * 420
        let reduceMotion = accessibilitySettings.resolvedReduceMotion(
            systemReduceMotion: systemReduceMotion
        )
        carNode.zRotation = reduceMotion ? 0 : -interpolatedLateral * 0.08
        roadNode.position.y = reduceMotion
            ? 0
            : CGFloat(interpolatedDistance.truncatingRemainder(dividingBy: 35))
        speedLabel.text = "AUTO  ◆  \(Int(state.speed * 2.4)) MPH"
        PerformanceInstrumentation.end(.roadProjection, roadInterval)

        let effectsInterval = PerformanceInstrumentation.begin(.effects)
        if quality.expensiveEffectsEnabled
            && !reduceMotion
            && !accessibilitySettings.reduceFlashes {
            let pulse = 0.88 + sin(currentTime * 4) * 0.05
            carNode.setScale(pulse)
        } else {
            carNode.setScale(0.88)
        }
        PerformanceInstrumentation.end(.effects, effectsInterval)
    }

    private func applyPalette() {
        let palette = PaletteComponents.resolve(
            accessibilitySettings.palette,
            highContrast: accessibilitySettings.highContrast
        )
        backgroundColor = palette.background.spriteColor
        if let grid = roadNode.childNode(withName: "road-grid") as? SKShapeNode {
            grid.strokeColor = palette.primary.spriteColor
            grid.glowWidth = accessibilitySettings.reduceFlashes ? 1 : 8 * CGFloat(quality.glowScale)
        }
        centerCueNode.strokeColor = palette.text.spriteColor
        carNode.fillColor = palette.secondary.spriteColor
        carNode.strokeColor = palette.primary.spriteColor
        carNode.glowWidth = accessibilitySettings.reduceFlashes ? 2 : 18 * CGFloat(quality.glowScale)
        speedLabel.fontColor = palette.text.spriteColor
        speedLabel.fontSize = accessibilitySettings.largeHUD ? 54 : 38
    }

    private func skylinePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -960, y: -20))

        var x: CGFloat = -960
        let widths: [CGFloat] = [120, 80, 145, 95, 170, 75, 110, 135, 90, 160, 105, 130]
        let heights: [CGFloat] = [150, 230, 120, 280, 190, 320, 175, 250, 135, 300, 205, 160]

        let buildingCount = max(1, Int(Double(widths.count) * quality.sceneryDensityScale))
        for index in widths.indices.prefix(buildingCount) {
            let width = widths[index]
            let height = heights[index]
            path.addLine(to: CGPoint(x: x, y: height))
            x += width
            path.addLine(to: CGPoint(x: x, y: height))
        }

        path.addLine(to: CGPoint(x: 960, y: -20))
        path.closeSubpath()
        return path
    }

}

private extension RGBColor {
    var spriteColor: SKColor {
        SKColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: 1
        )
    }
}

#if DEBUG
private extension SKNode {
    var nodeCountIncludingDescendants: Int {
        1 + children.reduce(0) { $0 + $1.nodeCountIncludingDescendants }
    }
}
#endif
