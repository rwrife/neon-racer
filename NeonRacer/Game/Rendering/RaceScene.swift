import SpriteKit

final class RaceScene: SKScene {
    var audioFrameHandler: ((EngineAudioInput, TimeInterval) -> Void)?
    var audioEventHandler: ((AudioEvent) -> Void)?
    var commandProvider: @MainActor () -> PlayerCommand = { .idle }
    var engineIntensityDidChange: @MainActor (Double) -> Void = { _ in }
    var feedbackDidOccur: @MainActor (HapticEvent) -> Void = { _ in }
    var raceDidEnd: @MainActor (RaceResult) -> Void = { _ in }
    var hudDidUpdate: @MainActor (RaceHUDUpdate) -> Void = { _ in }

    private var simulation: RaceSimulation
    private var hudTracker = RaceHUDTracker()
    private let configuration: RaceConfiguration
    private let routeName: String
    private let garagePalette: GaragePaletteDefinition
    private let quality: CosmeticQualityConfiguration
    private let hudRoot = SKNode()
    private lazy var effectsStack = NeonEffectsStack(
        sceneSize: size,
        quality: quality
    )
    private var previousUpdateTime: TimeInterval?
    private let carNode = VehicleArtNode(definition: VehicleArtCatalog.player)
    private var vehicleFrameSelector = VehicleFrameSelector()
    private let roadNode = SKNode()
    private var environmentRenderer: EnvironmentRenderer?
    private var environmentDiagnostics = EnvironmentDiagnostics.empty
    private var previousPhase = RacePhase.loading
    private var wasBoostActive = false
    private var observedFeedbackEventCount = 0
    private var damageVisualTimeRemaining: TimeInterval = 0
    private var didReportResult = false
    private let centerCueNode = SKShapeNode()
    private var accessibilitySettings = AccessibilitySettings.defaults
    private var systemReduceMotion = false
    private var lastHUDPublishTime: TimeInterval = -.infinity
#if DEBUG
    private let performanceMetrics = DebugPerformanceMetrics()
    private let performanceLabel = SKLabelNode(fontNamed: "Menlo")
#endif

    func apply(settings: AccessibilitySettings, systemReduceMotion: Bool) {
        accessibilitySettings = settings
        self.systemReduceMotion = systemReduceMotion
        effectsStack.apply(
            configuration: effectsStack.configuration,
            accessibility: NeonEffectsAccessibility(
                reduceMotion: settings.resolvedReduceMotion(
                    systemReduceMotion: systemReduceMotion
                ),
                reduceFlashes: settings.reduceFlashes
            )
        )
        applyPalette()
    }

    func apply(effects configuration: NeonEffectsConfiguration) {
        effectsStack.apply(
            configuration: configuration,
            accessibility: NeonEffectsAccessibility(
                reduceMotion: accessibilitySettings.resolvedReduceMotion(
                    systemReduceMotion: systemReduceMotion
                ),
                reduceFlashes: accessibilitySettings.reduceFlashes
            )
        )
        applyPalette()
    }

    func triggerCollisionEffects(intensity: Double = 1) {
        effectsStack.triggerCollision(intensity: intensity)
    }

    private func driveCollisionEffectsFromSimulation() {
        if simulation.feedbackEvents.count < observedFeedbackEventCount {
            observedFeedbackEventCount = 0
        }
        for event in simulation.feedbackEvents.dropFirst(observedFeedbackEventCount)
        where event.cue == .collisionPenalty {
            effectsStack.triggerCollision(intensity: 1)
            damageVisualTimeRemaining = 0.18
        }
        observedFeedbackEventCount = simulation.feedbackEvents.count
    }

    convenience init(
        configuration: RaceConfiguration = .standard,
        routeGraph: RouteGraph? = nil,
        routeName: String = "Neon Causeway",
        garagePalette: GaragePaletteDefinition = ProgressionCatalog.palettes[0]
    ) {
        self.init(
            size: CGSize(width: 1920, height: 1080),
            quality: .environmentDefault,
            configuration: configuration,
            routeGraph: routeGraph,
            routeName: routeName,
            garagePalette: garagePalette
        )
    }

    init(
        size: CGSize,
        quality: CosmeticQualityConfiguration,
        configuration: RaceConfiguration = .standard,
        routeGraph: RouteGraph? = nil,
        routeName: String = "Neon Causeway",
        garagePalette: GaragePaletteDefinition = ProgressionCatalog.palettes[0]
    ) {
        self.quality = quality
        self.configuration = configuration
        self.routeName = routeName
        self.garagePalette = garagePalette
        simulation = RaceSimulation(configuration: configuration, routeGraph: routeGraph)
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.015, green: 0.005, blue: 0.06, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        quality = .balanced
        configuration = .standard
        routeName = "Neon Causeway"
        garagePalette = ProgressionCatalog.palettes[0]
        simulation = RaceSimulation()
        super.init(coder: aDecoder)
    }

    override func didMove(to view: SKView) {
        guard children.isEmpty else {
            return
        }

        view.preferredFramesPerSecond = 120
        view.contentScaleFactor *= CGFloat(quality.renderTargetScale)
        hudRoot.name = "crisp-hud"
        hudRoot.zPosition = 1_000
        addChild(hudRoot)
        buildEnvironment()
        buildRoadGrid()
        buildCar()
        buildHUD()
        effectsStack.install(in: self, hudRoot: hudRoot)
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
        driveCollisionEffectsFromSimulation()
        let hudUpdate = hudTracker.update(
            state: simulation.state,
            events: simulation.events,
            scoreEvents: simulation.scoreEvents,
            feedbackEvents: simulation.feedbackEvents,
            runEvents: simulation.runEvents,
            configuration: configuration,
            trackLayout: simulation.trackLayout
        )
        if hudUpdate.feedback != nil || currentTime - lastHUDPublishTime >= 1.0 / 20.0 {
            hudDidUpdate(hudUpdate)
            lastHUDPublishTime = currentTime
        }

        render(
            snapshot: simulation.renderSnapshot,
            command: command,
            frameDelta: frameDelta,
            currentTime: currentTime
        )
        damageVisualTimeRemaining = max(0, damageVisualTimeRemaining - frameDelta)
        updateAudio(command: command, deltaTime: frameDelta)
        engineIntensityDidChange(
            simulation.state.speed / configuration.maximumSpeed
        )

#if DEBUG
        let effectsMetrics = effectsStack.metrics
        performanceLabel.text = performanceMetrics.record(
            frameDelta: frameDelta,
            activeVehicles: 1,
            segmentCount: 14,
            nodeCount: nodeCountIncludingDescendants,
            environmentDrawCount: environmentDiagnostics.estimatedDrawCount,
            environmentNodeCount: environmentDiagnostics.visibleNodeCount,
            qualityTier: quality.tier,
            activeEffects: effectsMetrics.activeEffects,
            activePooledNodes: effectsMetrics.activePooledNodes,
            pooledNodeCapacity: effectsMetrics.pooledNodeCapacity
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
        observedFeedbackEventCount = 0
        damageVisualTimeRemaining = 0
        commandProvider = { .idle }
        feedbackDidOccur = { _ in }
        engineIntensityDidChange = { _ in }
        raceDidEnd = { _ in }
        hudDidUpdate = { _ in }
    }

#if DEBUG
    func completeForUITesting(succeeded: Bool) -> RaceResult {
        if succeeded {
            simulation.finish()
        } else {
            simulation.fail()
        }
        didReportResult = true
        return makeResult()
    }
#endif

    private func updateAudio(command: PlayerCommand, deltaTime: TimeInterval) {
        let state = simulation.state
        let normalizedSpeed = state.speed / configuration.maximumSpeed
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
            case .racing where previousPhase == .paused:
                audioEventHandler?(.raceResumed)
            case .paused:
                audioEventHandler?(.racePaused)
            case .finished:
                audioEventHandler?(.finish)
            case .failed:
                audioEventHandler?(.failure)
            case .loading, .countdown, .racing, .checkpoint, .fork, .restarting:
                break
            }
            previousPhase = state.phase
        }

        reportResultIfNeeded()
    }

    private func reportResultIfNeeded() {
        let state = simulation.state
        guard !didReportResult, state.phase == .finished || state.phase == .failed else {
            return
        }
        didReportResult = true
        raceDidEnd(makeResult())
    }

    private func makeResult() -> RaceResult {
        RaceResult(
            state: simulation.state,
            rank: simulation.currentRank,
            routeName: routeName,
            scoreBreakdown: simulation.scoreResult.breakdown
        )
    }

    private func buildEnvironment() {
        let palette = PaletteComponents.resolve(
            accessibilitySettings.palette,
            highContrast: accessibilitySettings.highContrast
        )
        let environmentPalette = EnvironmentPalette.accessibility(palette)
        let renderer = EnvironmentRenderer(
            size: size,
            quality: quality,
            configuration: .demo(palette: environmentPalette)
        )
        environmentRenderer = renderer
        addChild(renderer.rootNode)
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
        carNode.position = CGPoint(x: 0, y: -330)
        carNode.zPosition = 20
        addChild(carNode)
    }

    private func buildHUD() {
#if DEBUG
        performanceLabel.fontSize = 22
        performanceLabel.fontColor = .white
        performanceLabel.numberOfLines = 4
        performanceLabel.horizontalAlignmentMode = .left
        performanceLabel.verticalAlignmentMode = .top
        performanceLabel.position = CGPoint(x: -930, y: 500)
        performanceLabel.zPosition = 100
        hudRoot.addChild(performanceLabel)
#endif
    }

    private func render(
        snapshot: RaceRenderSnapshot,
        command: PlayerCommand,
        frameDelta: TimeInterval,
        currentTime: TimeInterval
    ) {
        let roadInterval = PerformanceInstrumentation.begin(.roadProjection)
        let alpha = CGFloat(snapshot.interpolationAlpha)
        let interpolatedLateral = CGFloat(snapshot.previous.lateralPosition) * (1 - alpha)
            + CGFloat(snapshot.current.lateralPosition) * alpha
        let interpolatedDistance = snapshot.previous.distance * (1 - Double(alpha))
            + snapshot.current.distance * Double(alpha)
        let state = snapshot.current
        let reduceMotion = accessibilitySettings.resolvedReduceMotion(
            systemReduceMotion: systemReduceMotion
        )
        let normalizedSpeed = state.speed / configuration.maximumSpeed
        let frame = vehicleFrameSelector.select(
            input: VehicleVisualInput(
                steering: command.steering,
                drift: abs(command.steering) * normalizedSpeed,
                brake: command.brake,
                boost: state.isBoostActive,
                damage: damageVisualTimeRemaining > 0 ? 1 : 0
            ),
            deltaTime: frameDelta
        )
        carNode.apply(frame: frame, reducedMotion: reduceMotion)

        carNode.position.x = interpolatedLateral * 420
        carNode.zRotation = reduceMotion ? 0 : -interpolatedLateral * 0.08
        roadNode.position.y = reduceMotion
            ? 0
            : CGFloat(interpolatedDistance.truncatingRemainder(dividingBy: 35))
        environmentDiagnostics = environmentRenderer?.update(
            projection: EnvironmentProjection(
                distance: interpolatedDistance,
                lateralOffset: interpolatedLateral,
                horizonY: 40,
                foregroundY: -540,
                horizonHalfWidth: 80,
                foregroundHalfWidth: 900,
                curveOffset: 0,
                elevationOffset: 0,
                visibleDistance: 900
            ),
            deltaTime: frameDelta,
            currentTime: currentTime,
            reduceMotion: reduceMotion
        ) ?? .empty
        PerformanceInstrumentation.end(.roadProjection, roadInterval)

        let effectsInterval = PerformanceInstrumentation.begin(.effects)
        if effectsStack.effectiveIntensity(for: .bloom) > 0
            && quality.expensiveEffectsEnabled
            && !reduceMotion
        {
            let pulse = 0.88 + sin(currentTime * 4) * 0.05
            carNode.setScale(pulse)
        } else {
            carNode.setScale(0.88)
        }
        effectsStack.update(
            NeonEffectsDrivers(
                normalizedSpeed: normalizedSpeed,
                boost: state.isBoostActive ? 1 : 0,
                steering: command.steering,
                offRoad: max(0, abs(state.lateralPosition) - 0.82) / 0.18,
                carPosition: carNode.position,
                currentTime: currentTime,
                deltaTime: frameDelta
            )
        )
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
            grid.glowWidth = CGFloat(
                8 * quality.glowScale * effectsStack.effectiveIntensity(for: .bloom)
            )
        }
        centerCueNode.strokeColor = palette.text.spriteColor
        let vehiclePalette: VehiclePaletteVariant
        if accessibilitySettings.highContrast || accessibilitySettings.palette != .neon {
            vehiclePalette = VehiclePaletteVariant(settings: accessibilitySettings)
        } else {
            vehiclePalette = switch garagePalette.id {
            case "solar-flare": .hardSignal
            case "ion-storm": .blueOrange
            default: .electricDusk
            }
        }
        carNode.apply(
            palette: vehiclePalette,
            reducedEffects: effectsStack.effectiveIntensity(for: .bloom) <= 0.05
                || !quality.expensiveEffectsEnabled
        )
        if environmentRenderer != nil {
            environmentRenderer?.transition(
                to: .accessibility(palette),
                duration: accessibilitySettings.reduceFlashes ? 0 : 0.45
            )
        }
    }

#if DEBUG
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self),
              effectsStack.toggleDebugEffect(at: point) else {
            super.touchesBegan(touches, with: event)
            return
        }
        applyPalette()
    }
#endif

}

#if DEBUG
private extension SKNode {
    var nodeCountIncludingDescendants: Int {
        1 + children.reduce(0) { $0 + $1.nodeCountIncludingDescendants }
    }
}
#endif
