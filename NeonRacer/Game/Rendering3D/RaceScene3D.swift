import Foundation
import QuartzCore
import SceneKit
import UIKit

@MainActor
final class RaceScene3D: NSObject {
    let scene = SCNScene()

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
    private var quality: CosmeticQualityConfiguration
    private let renderQualityPreference: RenderQualityPreference
    private var renderQuality: RenderQualityConfiguration
    private let mapper: TrackWorldMapper3D
    private let terrain = NeonTerrain3D()
    private let roadBuilder = RoadMeshBuilder3D()
    private let tunnelBuilder = TunnelMeshBuilder3D()
    private let markerBuilder = TrackMarkers3D()
    private let chaseCamera = ChaseCamera3D()
    private let environment: NeonEnvironment3D
    private let effects = NeonEffects3D()
    private let roadsideProps = RoadsidePropStreamer3D()
    private let carNode: NeonCarNode
    private var trafficNodes: [UInt64: NeonCarNode] = [:]
    private var obstacleNodes: [UInt64: SCNNode] = [:]
    private weak var attachedView: SCNView?
    private var displayLink: CADisplayLink?
    private var previousUpdateTime: TimeInterval?
    private var previousPhase = RacePhase.loading
    private var wasBoostActive = false
    private var didReportResult = false
    private var finishCruise = FinishCruiseState()
    private var accessibilitySettings = AccessibilitySettings.defaults
    private var systemReduceMotion = false
    private var lastHUDPublishTime: TimeInterval = -.infinity
    private var observedRaceEventCount = 0
    private var observedScoreEventCount = 0
    private var observedFeedbackEventCount = 0
    private var observedRunEventCount = 0
    private var lastEnvironmentID = ""
    private var heroCenterHeight: Float = 0.6
    private var wasWipingOut = false
    private var previousWipeoutElapsed: Double = 0
#if DEBUG
    private let performanceMetrics = DebugPerformanceMetrics()
    private(set) var debugPerformanceSnapshot: DebugPerformanceSnapshot?
    var debugRaceState: RaceState { simulation.state }

    func advanceForTesting(frameDelta: TimeInterval, currentTime: TimeInterval) {
        step(frameDelta: frameDelta, currentTime: currentTime)
    }
#endif
    private var thermalObserver: NSObjectProtocol?

    convenience init(
        renderQualityPreference: RenderQualityPreference = .automatic,
        configuration: RaceConfiguration = .standard,
        routeGraph: RouteGraph? = nil,
        routeName: String = "Neon Causeway",
        garagePalette: GaragePaletteDefinition = ProgressionCatalog.palettes[0],
        selectedVehicleID: String = "prototype-zero"
    ) {
        self.init(
            quality: .environmentDefault,
            renderQualityPreference: renderQualityPreference,
            configuration: configuration,
            routeGraph: routeGraph,
            routeName: routeName,
            garagePalette: garagePalette,
            selectedVehicleID: selectedVehicleID
        )
    }

    init(
        quality: CosmeticQualityConfiguration,
        renderQualityPreference: RenderQualityPreference = .automatic,
        configuration: RaceConfiguration = .standard,
        routeGraph: RouteGraph? = nil,
        routeName: String = "Neon Causeway",
        garagePalette: GaragePaletteDefinition = ProgressionCatalog.palettes[0],
        selectedVehicleID: String = "prototype-zero"
    ) {
        let selectedRenderQuality = if renderQualityPreference == .automatic,
                                       ProcessInfo.processInfo.environment["NEON_RACER_QUALITY_TIER"] != nil {
            RenderQualityConfiguration.preset(for: RenderQualityTier(cosmeticTier: quality.tier))
        } else {
            RenderQualityConfiguration.selected(preference: renderQualityPreference)
        }
        self.renderQualityPreference = renderQualityPreference
        self.renderQuality = selectedRenderQuality
        self.quality = CosmeticQualityConfiguration.preset(for: selectedRenderQuality.tier)
        self.configuration = configuration
        self.routeName = routeName
        self.garagePalette = garagePalette
        self.simulation = RaceSimulation(configuration: configuration, routeGraph: routeGraph)
        self.mapper = TrackWorldMapper3D(layout: simulation.trackLayout)
        self.environment = NeonEnvironment3D(quality: quality.tier)
        self.carNode = VehicleModels3D.makeHeroCar(vehicleID: selectedVehicleID, paletteID: garagePalette.id)
        super.init()
        buildScene()
    }

    func attach(to view: SCNView) {
        attachedView = view
        view.scene = scene
        view.pointOfView = chaseCamera.cameraNode
        view.preferredFramesPerSecond = 60
        view.isJitteringEnabled = false
        view.isPlaying = true
        view.rendersContinuously = true
        view.allowsCameraControl = false
        effects.install(on: view)
        let selectedRenderQuality = if renderQualityPreference == .automatic,
                                       ProcessInfo.processInfo.environment["NEON_RACER_QUALITY_TIER"] != nil {
            renderQuality
        } else {
            RenderQualityConfiguration.selected(preference: renderQualityPreference)
        }
        applyRenderQuality(selectedRenderQuality, to: view)
        observeThermalStateIfNeeded()
        step(frameDelta: 0, currentTime: CACurrentMediaTime())
        startDisplayLinkIfNeeded()
    }

    func apply(settings: AccessibilitySettings, systemReduceMotion: Bool) {
        accessibilitySettings = settings
        self.systemReduceMotion = systemReduceMotion
        let reduceMotion = settings.resolvedReduceMotion(systemReduceMotion: systemReduceMotion)
        chaseCamera.apply(reduceMotion: reduceMotion)
        environment.apply(reduceMotion: reduceMotion, highContrast: settings.highContrast)
        effects.apply(
            reduceMotion: reduceMotion,
            reduceFlashing: settings.reduceFlashes,
            intensity: quality.expensiveEffectsEnabled ? 1 : 0.45
        )
    }

    private func observeThermalStateIfNeeded() {
        guard thermalObserver == nil else { return }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyRenderQuality(
                    RenderQualityConfiguration.selected(preference: self?.renderQualityPreference ?? .automatic)
                )
            }
        }
    }

    private func applyRenderQuality(_ configuration: RenderQualityConfiguration, to view: SCNView? = nil) {
        guard configuration != renderQuality || view != nil else { return }
        renderQuality = configuration
        quality = CosmeticQualityConfiguration.preset(for: configuration.tier)
        let targetView = view ?? attachedView
        if let targetView {
            targetView.contentScaleFactor = targetView.traitCollection.displayScale * CGFloat(configuration.contentScale)
        }
#if targetEnvironment(simulator)
        targetView?.antialiasingMode = .none
#else
        switch configuration.antialiasing {
        case .none:
            targetView?.antialiasingMode = .none
        case .multisampling2X:
            targetView?.antialiasingMode = .multisampling2X
        case .multisampling4X:
            targetView?.antialiasingMode = .multisampling4X
        }
#endif
        environment.apply(renderQualityTier: configuration.tier)
        effects.apply(quality: quality.tier)
        effects.apply(renderQuality: configuration)
        apply(settings: accessibilitySettings, systemReduceMotion: systemReduceMotion)
    }

    func triggerCollisionEffects(intensity: Double = 1) {
        effects.trigger(.collision(intensity: intensity))
        chaseCamera.triggerShake(intensity: intensity)
    }

    func pauseForInterruption() {
        simulation.setPaused(true)
        previousUpdateTime = nil
        displayLink?.isPaused = true
        attachedView?.isPlaying = false
        attachedView?.rendersContinuously = false
        engineIntensityDidChange(0)
    }

    func resumeAfterInterruption() {
        previousUpdateTime = nil
        simulation.setPaused(false)
        displayLink?.isPaused = false
        attachedView?.isPlaying = true
        attachedView?.rendersContinuously = true
        attachedView?.setNeedsDisplay()
    }

    func releaseRecreatableResourcesForMemoryPressure() {
        for node in trafficNodes.values {
            node.removeFromParentNode()
        }
        trafficNodes.removeAll(keepingCapacity: true)
        for node in obstacleNodes.values {
            node.removeFromParentNode()
        }
        obstacleNodes.removeAll(keepingCapacity: true)
        roadsideProps.releaseRecreatableResources()
    }

    func tearDown() {
        pauseForInterruption()
        displayLink?.invalidate()
        displayLink = nil
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
        attachedView = nil
        commandProvider = { .idle }
        feedbackDidOccur = { _ in }
        engineIntensityDidChange = { _ in }
        raceDidEnd = { _ in }
        hudDidUpdate = { _ in }
        audioFrameHandler = nil
        audioEventHandler = nil
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

    private func buildScene() {
        scene.rootNode.name = "race-3d-root"
        scene.rootNode.addChildNode(terrain.rootNode)
        scene.rootNode.addChildNode(roadBuilder.rootNode)
        scene.rootNode.addChildNode(markerBuilder.rootNode)
        scene.rootNode.addChildNode(roadsideProps.rootNode)
        normalizeHeroCarScaleIfNeeded()
        let heroBounds = heroCarBounds()
        heroCenterHeight = max(0.3, (heroBounds.minimum.y + heroBounds.maximum.y) * 0.5)
        chaseCamera.configureSubject(
            length: heroBounds.dimensions.z,
            height: heroBounds.dimensions.y,
            rearOverhang: heroBounds.maximum.z
        )
        scene.rootNode.addChildNode(carNode)
        scene.rootNode.addChildNode(chaseCamera.cameraNode)
        scene.rootNode.addChildNode(tunnelBuilder.rootNode)
        environment.attach(to: scene)
        if let camera = chaseCamera.cameraNode.camera {
            effects.configure(camera: camera)
        }
        effects.apply(quality: quality.tier)
        effects.apply(renderQuality: renderQuality)
        environment.apply(renderQualityTier: renderQuality.tier)
        effects.attach(to: scene, carNode: carNode, cameraNode: chaseCamera.cameraNode)
        mapper.updateRoute(for: simulation.state)
        lastEnvironmentID = simulation.state.currentEnvironmentID
        environment.setEnvironment(lastEnvironmentID, animated: false)
    }

    private func normalizeHeroCarScaleIfNeeded() {
        let dimensions = heroCarBounds().dimensions
        guard dimensions.z > 0.01 else { return }
        let targetLength: Float = 4.45
        let scaleFactor = targetLength / dimensions.z
        if scaleFactor < 0.55 || scaleFactor > 1.55 {
            carNode.scale = SCNVector3(
                carNode.scale.x * scaleFactor,
                carNode.scale.y * scaleFactor,
                carNode.scale.z * scaleFactor
            )
        }
    }

    private func heroCarBounds() -> (minimum: SCNVector3, maximum: SCNVector3, dimensions: SCNVector3) {
        var minimum = SCNVector3Zero
        var maximum = SCNVector3Zero
        carNode.getBoundingBoxMin(&minimum, max: &maximum)
        let scale = carNode.scale
        let scaledMinimum = SCNVector3(minimum.x * scale.x, minimum.y * scale.y, minimum.z * scale.z)
        let scaledMaximum = SCNVector3(maximum.x * scale.x, maximum.y * scale.y, maximum.z * scale.z)
        return (
            scaledMinimum,
            scaledMaximum,
            SCNVector3(
                abs(scaledMaximum.x - scaledMinimum.x),
                abs(scaledMaximum.y - scaledMinimum.y),
                abs(scaledMaximum.z - scaledMinimum.z)
            )
        )
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(owner: self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func displayLinkDidTick(_ link: CADisplayLink) {
        let currentTime = link.timestamp
        let frameDelta = previousUpdateTime.map { min(currentTime - $0, 0.1) } ?? 0
        previousUpdateTime = currentTime
        step(frameDelta: frameDelta, currentTime: currentTime)
    }

    private func step(frameDelta: TimeInterval, currentTime: TimeInterval) {
        let frameInterval = PerformanceInstrumentation.begin(.frame)
        defer { PerformanceInstrumentation.end(.frame, frameInterval) }

        var command = commandProvider()
#if DEBUG
        if Self.debugAutoDrive {
            command = debugAutoDriveCommand()
        }
#endif
        simulation.advance(frameDelta: frameDelta, command: command)
        if simulation.state.phase == .finished, !finishCruise.isActive {
            finishCruise.begin(
                outcome: .finished,
                currentSpeed: simulation.state.speed,
                routeDistance: simulation.state.distance
            )
        }
        finishCruise.advance(deltaTime: frameDelta)
        mapper.updateRoute(
            for: simulation.state,
            presentationDistance: finishCruise.isActive ? finishCruise.presentationDistance : nil
        )
        driveFeedbackFromSimulation()
        publishHUDIfNeeded(currentTime: currentTime)
        render(snapshot: simulation.renderSnapshot, command: command, frameDelta: frameDelta, currentTime: currentTime)
        updateAudio(command: command, deltaTime: frameDelta)
        engineIntensityDidChange(simulation.state.speed / configuration.maximumSpeed)
        handlePhaseAudio()
        reportResultIfNeeded()
    }

#if DEBUG
    private static let debugAutoDrive = ProcessInfo.processInfo.arguments.contains("UITestAutoDrive")

    /// Debug-only autopilot for visual capture: full throttle, dodges the nearest thing ahead.
    private func debugAutoDriveCommand() -> PlayerCommand {
        let state = simulation.state
        var target = 0.0
        if let cross = simulation.trackLayout.splitCrossSection(stageID: state.currentStageID,
                                                                distanceInStage: state.currentStageDistance + 35) {
            let useRight = ProcessInfo.processInfo.arguments.contains("UITestSplitRight")
            target = (useRight ? cross.rightCenter : cross.leftCenter) / cross.roadHalfWidth
        }
        let threats = state.traffic.map { ($0.distance, $0.lateralPosition) }
            + state.obstacles.filter { !$0.isHit && abs($0.lateralPosition) < 1 }.map { ($0.distance, $0.lateralPosition) }
        if let threat = threats
            .filter({ $0.0 > state.distance && $0.0 < state.distance + 70 })
            .min(by: { $0.0 < $1.0 }) {
            target = threat.1 > 0 ? -0.5 : 0.5
        }
        let sample = simulation.trackLayout.drivingSample(stageID: state.currentStageID,
                                                          distanceInStage: state.currentStageDistance,
                                                          splitSide: state.splitRoadSide)
        let speedRatio = min(state.speed / configuration.maximumSpeed, 1)
        let authority = configuration.driving.steeringAtRestRatio + (1 - configuration.driving.steeringAtRestRatio) * speedRatio
        var lateralError = target - state.lateralPosition
        if let side = state.splitRoadSide,
           let path = simulation.trackLayout.splitPath(stageID: state.currentStageID, distanceInStage: state.currentStageDistance, side: side) {
            let cross = simulation.trackLayout.sample(stageID: state.currentStageID, distanceInStage: state.currentStageDistance)
            lateralError = -(state.lateralPosition * cross.roadHalfWidth - path.center) / path.halfWidth
        }
        let counterSteer = sample.curvature * state.speed * state.speed * configuration.driving.centrifugalForce
            / max(0.1, configuration.steeringRate * authority)
        let steering = min(max(counterSteer + lateralError * 2.2, -1), 1)
        return PlayerCommand(steering: steering, throttle: 1, brake: 0, isBoosting: state.boostCharge > 1.5)
    }

#endif

    private func publishHUDIfNeeded(currentTime: TimeInterval) {
        let update = hudTracker.update(
            state: simulation.state,
            events: simulation.events,
            scoreEvents: simulation.scoreEvents,
            feedbackEvents: simulation.feedbackEvents,
            runEvents: simulation.runEvents,
            configuration: configuration,
            trackLayout: simulation.trackLayout
        )
        if update.feedback != nil || currentTime - lastHUDPublishTime >= 1.0 / 20.0 {
            hudDidUpdate(update)
            lastHUDPublishTime = currentTime
        }
    }

    private func render(
        snapshot: RaceRenderSnapshot,
        command: PlayerCommand,
        frameDelta: TimeInterval,
        currentTime: TimeInterval
    ) {
        let roadInterval = PerformanceInstrumentation.begin(.roadProjection)
        let alpha = snapshot.interpolationAlpha
        let state = snapshot.current
        // Respawn teleports the car to the road center; don't interpolate across the jump.
        let didRespawn = snapshot.previous.vehicle.isWipingOut && !state.vehicle.isWipingOut
        let lateralAlpha = didRespawn ? 1 : alpha
        let distance = finishCruise.isActive
            ? finishCruise.presentationDistance
            : interpolate(snapshot.previous.distance, snapshot.current.distance, alpha)
        let lateral = interpolate(snapshot.previous.lateralPosition, snapshot.current.lateralPosition, lateralAlpha)
        let speed = finishCruise.isActive
            ? finishCruise.presentationSpeed
            : interpolate(snapshot.previous.speed, snapshot.current.speed, alpha)
        let carFrame = mapper.actorFrame(atRunDistance: distance, lateralPosition: lateral, splitSide: state.splitRoadSide)
        carNode.position = carFrame.position
        carNode.eulerAngles = SCNVector3(
            carFrame.pitch,
            carFrame.yaw - Float(state.vehicle.roadPosition.heading * 0.35),
            0
        )
        applyWipeoutPose(snapshot: snapshot, alpha: alpha, carFrame: carFrame, currentTime: currentTime)
        carNode.update(
            steering: state.vehicle.isWipingOut ? 0 : command.steering,
            speed: speed,
            isBoosting: state.isBoostActive,
            isBraking: command.brake > 0.2,
            slipAngle: state.vehicle.slipAngle,
            time: currentTime
        )
        roadBuilder.update(playerDistance: distance, mapper: mapper)
        tunnelBuilder.update(playerDistance: distance, mapper: mapper)
        terrain.update(playerDistance: distance, mapper: mapper, renderQuality: renderQuality)
        roadsideProps.update(
            playerDistance: distance,
            mapper: mapper,
            environment: environment,
            drawDistance: renderQuality.drawDistanceMeters
        )
        markerBuilder.update(state: state, mapper: mapper)
        if finishCruise.isActive {
            removeCourseHazards()
        } else {
            updateTraffic(snapshot: snapshot, alpha: alpha)
            updateObstacles(snapshot: snapshot, alpha: alpha)
        }
        PerformanceInstrumentation.end(.roadProjection, roadInterval)

        let effectsInterval = PerformanceInstrumentation.begin(.effects)
        let speedRatio = speed / configuration.maximumSpeed
        chaseCamera.update(
            carFrame: carFrame,
            speedRatio: speedRatio,
            isBoosting: state.isBoostActive,
            steering: command.steering,
            deltaTime: frameDelta,
            time: currentTime,
            tunnelBlend: mapper.layout.tunnel(for: carFrame.stageID)?.cameraBlend(at: carFrame.distanceInStage) ?? 0
        )
        environment.groundLevel = carFrame.position.y
        environment.update(
            cameraPosition: chaseCamera.currentPosition,
            cameraForward: chaseCamera.currentForward,
            time: currentTime,
            speedRatio: speedRatio
        )
        effects.setPose(carPosition: carFrame.position, cameraForward: chaseCamera.currentForward)
        effects.update(
            speedRatio: speedRatio,
            isBoosting: state.isBoostActive,
            isDrifting: state.vehicle.isDrifting,
            isOffRoad: state.vehicle.isOffRoad,
            time: currentTime
        )
        PerformanceInstrumentation.end(.effects, effectsInterval)
#if DEBUG
        debugPerformanceSnapshot = performanceMetrics.record(
            frameDelta: frameDelta,
            activeVehicles: trafficNodes.count + 1,
            segmentCount: roadBuilder.activeChunkCount,
            nodeCount: scene.rootNode.nrRecursiveNodeCount,
            environmentDrawCount: scene.rootNode.nrGeometryNodeCount,
            environmentNodeCount: environment.rootNode.childNodes.count,
            qualityTier: quality.tier,
            activeEffects: state.isBoostActive ? 1 : 0,
            activePooledNodes: trafficNodes.count + obstacleNodes.count + roadsideProps.activeNodeCount,
            pooledNodeCapacity: trafficNodes.count + obstacleNodes.count + roadsideProps.activeNodeCount
        )
#endif
    }

    /// Crash tumble: the car is launched, barrel-rolls and spins, lands with sparks, then
    /// dissolves and rematerializes at the road center, blinking while the respawn shield is up.
    private func applyWipeoutPose(
        snapshot: RaceRenderSnapshot,
        alpha: Double,
        carFrame: TrackWorldFrame3D,
        currentTime: TimeInterval
    ) {
        let vehicle = snapshot.current.vehicle
        guard vehicle.isWipingOut else {
            if wasWipingOut {
                wasWipingOut = false
                previousWipeoutElapsed = 0
                effects.trigger(.checkpoint)
            }
            carNode.opacity = vehicle.respawnShieldRemaining > 0
                ? (sin(currentTime * 28) > 0 ? 1 : 0.3)
                : 1
            return
        }
        wasWipingOut = true

        let duration = max(vehicle.wipeoutDuration, 0.001)
        let previousRemaining = snapshot.previous.vehicle.isWipingOut
            ? snapshot.previous.vehicle.wipeoutRemaining
            : duration
        let remaining = interpolate(previousRemaining, vehicle.wipeoutRemaining, alpha)
        let elapsed = min(max(duration - remaining, 0), duration)
        let direction = vehicle.wipeoutDirection == 0 ? 1.0 : vehicle.wipeoutDirection
        let severity = min(max(vehicle.wipeoutSeverity, 0), 1)
        let reduceMotion = accessibilitySettings.resolvedReduceMotion(systemReduceMotion: systemReduceMotion)

        let airTime = 0.85 + 0.35 * severity
        let peakHeight = reduceMotion ? 0.35 : 1.0 + 1.1 * severity
        var lift = 0.0
        if elapsed < airTime {
            let u = elapsed / airTime
            lift = 4 * peakHeight * u * (1 - u)
        } else if elapsed < airTime + 0.4 {
            let u = (elapsed - airTime) / 0.4
            lift = 4 * peakHeight * 0.18 * u * (1 - u)
        }
        if previousWipeoutElapsed < airTime, elapsed >= airTime {
            effects.trigger(.collision(intensity: 0.55 + 0.35 * severity))
        }
        previousWipeoutElapsed = elapsed

        let flips = reduceMotion ? 0.0 : (severity > 0.6 ? 2.0 : 1.0)
        let rollProgress = smoothStep(min(max(elapsed / (airTime + 0.15), 0), 1))
        let roll = direction * 2 * .pi * flips * rollProgress
        let spinTurns = reduceMotion ? 0.25 : 1.0 + severity
        let spinProgress = 1 - pow(1 - elapsed / duration, 3)
        let spin = -direction * 2 * .pi * spinTurns * spinProgress
        let pitchWobble = reduceMotion ? 0 : sin(elapsed * 9) * 0.35 * (1 - elapsed / duration)

        let base = carNode.simdOrientation
        let local = simd_quatf(angle: Float(spin), axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: Float(roll), axis: SIMD3<Float>(0, 0, -1))
            * simd_quatf(angle: Float(pitchWobble), axis: SIMD3<Float>(1, 0, 0))
        let orientation = base * local
        let center = SIMD3<Float>(0, heroCenterHeight, 0)
        carNode.simdOrientation = orientation
        carNode.simdPosition = carNode.simdPosition
            + SIMD3<Float>(0, Float(lift), 0)
            + base.act(center)
            - orientation.act(center)

        let dissolveStart = duration - 0.3
        carNode.opacity = elapsed > dissolveStart
            ? CGFloat(max(0, 1 - (elapsed - dissolveStart) / 0.3))
            : 1
    }

    private func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    private func updateTraffic(snapshot: RaceRenderSnapshot, alpha: Double) {
        let previous = Dictionary(uniqueKeysWithValues: snapshot.previous.traffic.map { ($0.id, $0) })
        var active: Set<UInt64> = []
        for current in snapshot.current.traffic where current.distance > snapshot.current.distance - 60 && current.distance < snapshot.current.distance + renderQuality.drawDistanceMeters {
            active.insert(current.id)
            let node = trafficNodes[current.id] ?? {
                let made = VehicleModels3D.makeTrafficVehicle(kind: current.kind, seed: current.id)
                trafficNodes[current.id] = made
                scene.rootNode.addChildNode(made)
                return made
            }()
            let old = previous[current.id] ?? current
            let distance = interpolate(old.distance, current.distance, alpha)
            let lateral = interpolate(old.lateralPosition, current.lateralPosition, alpha)
            let frame = mapper.actorFrame(atRunDistance: distance, lateralPosition: lateral)
            node.position = frame.position
            node.eulerAngles = SCNVector3(frame.pitch, frame.yaw - Float(current.steering) * 0.08, 0)
            node.update(steering: current.steering, speed: current.speed, isBoosting: false, isBraking: current.isBraking, slipAngle: 0, time: CACurrentMediaTime())
            node.opacity = current.hasBeenPassed ? 0.75 : 1
        }
        for (id, node) in trafficNodes where !active.contains(id) {
            node.removeFromParentNode()
            trafficNodes[id] = nil
        }
    }

    private func updateObstacles(snapshot: RaceRenderSnapshot, alpha: Double) {
        let previous = Dictionary(uniqueKeysWithValues: snapshot.previous.obstacles.map { ($0.id, $0) })
        var active: Set<UInt64> = []
        for current in snapshot.current.obstacles where current.distance > snapshot.current.distance - 60 && current.distance < snapshot.current.distance + renderQuality.drawDistanceMeters {
            active.insert(current.id)
            let node = obstacleNodes[current.id] ?? {
                let made = VehicleModels3D.makeObstacle(kind: current.kind)
                obstacleNodes[current.id] = made
                scene.rootNode.addChildNode(made)
                return made
            }()
            let old = previous[current.id] ?? current
            let distance = interpolate(old.distance, current.distance, alpha)
            let lateral = interpolate(old.lateralPosition, current.lateralPosition, alpha)
            let frame = mapper.actorFrame(atRunDistance: distance, lateralPosition: lateral)
            node.position = frame.position
            node.eulerAngles = SCNVector3(frame.pitch, frame.yaw, 0)
            node.opacity = current.isHit ? 0.22 : 1
        }
        for (id, node) in obstacleNodes where !active.contains(id) {
            node.removeFromParentNode()
            obstacleNodes[id] = nil
        }
    }

    private func removeCourseHazards() {
        for node in trafficNodes.values { node.removeFromParentNode() }
        trafficNodes.removeAll(keepingCapacity: true)
        for node in obstacleNodes.values { node.removeFromParentNode() }
        obstacleNodes.removeAll(keepingCapacity: true)
    }

    private func driveFeedbackFromSimulation() {
        if observedRaceEventCount > simulation.events.count { observedRaceEventCount = 0 }
        if observedScoreEventCount > simulation.scoreEvents.count { observedScoreEventCount = 0 }
        if observedFeedbackEventCount > simulation.feedbackEvents.count { observedFeedbackEventCount = 0 }
        if observedRunEventCount > simulation.runEvents.count { observedRunEventCount = 0 }

        for event in simulation.events.dropFirst(observedRaceEventCount) {
            switch event {
            case .boostStarted:
                feedbackDidOccur(.boost)
                audioEventHandler?(.boost)
                effects.trigger(.boostStart)
            case .boostEnded:
                effects.trigger(.boostEnd)
            case .finished:
                // Finish/failure audio comes from handlePhaseAudio().
                effects.trigger(.finish)
            case .failed:
                effects.trigger(.crash)
            case .started:
                break
            }
        }
        observedRaceEventCount = simulation.events.count

        // One physical moment is reported on several streams; merge so it fires feedback once per frame.
        var collisionIntensity: Double?
        var checkpointCrossed = false
        func noteCollision(_ intensity: Double) {
            collisionIntensity = max(collisionIntensity ?? 0, intensity)
        }

        for event in simulation.scoreEvents.dropFirst(observedScoreEventCount) {
            switch event.source {
            case .overtake:
                audioEventHandler?(.pass)
                effects.trigger(.overtake)
            case .nearMiss:
                feedbackDidOccur(.nearMiss)
                audioEventHandler?(.nearMiss)
                effects.trigger(.nearMiss)
            case .checkpoint:
                checkpointCrossed = true
            case .collision:
                noteCollision(1)
            default:
                break
            }
        }
        observedScoreEventCount = simulation.scoreEvents.count

        for event in simulation.feedbackEvents.dropFirst(observedFeedbackEventCount) {
            switch event.cue {
            case .collisionPenalty, .crash, .obstacleHit, .timePenalty:
                noteCollision(event.cue == .timePenalty ? 0.75 : 1)
            default:
                break
            }
        }
        observedFeedbackEventCount = simulation.feedbackEvents.count

        for event in simulation.runEvents.dropFirst(observedRunEventCount) {
            switch event {
            case .stageChanged(_, _, let environmentID):
                if environmentID != lastEnvironmentID {
                    lastEnvironmentID = environmentID
                    environment.setEnvironment(environmentID, animated: !accessibilitySettings.reduceFlashes)
                    audioEventHandler?(.environmentChanged(environmentID.audioEnvironment))
                }
            case .checkpointCrossed:
                checkpointCrossed = true
            case .timePenalty(_, let seconds):
                noteCollision(min(max(seconds / 5, 0.45), 1))
            default:
                break
            }
        }
        observedRunEventCount = simulation.runEvents.count

        if checkpointCrossed {
            feedbackDidOccur(.checkpoint)
            audioEventHandler?(.checkpoint)
            effects.trigger(.checkpoint)
        }
        if let collisionIntensity {
            feedbackDidOccur(.collision)
            audioEventHandler?(.crash(severity: collisionIntensity))
            effects.trigger(.crash)
            triggerCollisionEffects(intensity: collisionIntensity)
        }
    }

    private func handlePhaseAudio() {
        let state = simulation.state
        guard state.phase != previousPhase else { return }
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

    private func reportResultIfNeeded() {
        let state = simulation.state
        guard !didReportResult, state.phase == .finished || state.phase == .failed else { return }
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
                collisionRecovery: state.vehicle.crashRecoveryRemaining
            ),
            deltaTime
        )
    }

    private func interpolate(_ previous: Double, _ current: Double, _ alpha: Double) -> Double {
        previous * (1 - alpha) + current * alpha
    }
}

@MainActor
final class RoadsidePropStreamer3D {
    let rootNode = SCNNode()
    private var nodes: [String: SCNNode] = [:]
    private let behindDistance = 80.0
    private let maximumNewPropsPerFrame = 2
    private let maximumRetiredPropsPerFrame = 4

    var activeNodeCount: Int { nodes.count }
#if DEBUG
    var debugActivePropKeys: Set<String> { Set(nodes.keys) }
#endif

    init() {
        rootNode.name = "roadside-prop-stream-root"
    }

    func update(
        playerDistance: Double,
        mapper: TrackWorldMapper3D,
        environment: NeonEnvironment3D,
        drawDistance: Double
    ) {
        var activeKeys: Set<String> = []
        var newPropsRemaining = maximumNewPropsPerFrame

        for placement in mapper.placements {
            let visibleStart = max(placement.startRunDistance, playerDistance - behindDistance)
            let visibleEnd = min(placement.endRunDistance, playerDistance + drawDistance)
            guard visibleStart < visibleEnd else { continue }
            let themeID = environment.themeID(for: placement.stage.environmentID)
            let kinds = environment.roadsidePropKinds(for: themeID)
            guard !kinds.isEmpty else { continue }
            let spacing = max(28, environment.roadsidePropSpacingHint(for: themeID))
            let startIndex = Int(floor(visibleStart / spacing))
            let endIndex = Int(ceil(visibleEnd / spacing))
            let billboardKinds = kinds.filter { kind in
                let normalized = kind.lowercased()
                return normalized.contains("billboard") || normalized.contains("sign")
            }

            for index in startIndex...endIndex {
                let seed = Self.seed(environmentID: themeID, index: index)
                let stationDistance = Double(index) * spacing + Double(seed % 17) * 0.73
                guard stationDistance >= visibleStart, stationDistance < visibleEnd else { continue }
                if let tunnel = mapper.layout.tunnel(for: placement.stage.id),
                   tunnel.contains(stationDistance - placement.startRunDistance) { continue }
                let wantsBillboard = abs(index) <= 6 || index.isMultiple(of: 4)
                let selectableKinds = wantsBillboard && !billboardKinds.isEmpty ? billboardKinds : kinds
                let kind = selectableKinds[Int(seed % UInt64(selectableKinds.count))]

                if kind.localizedCaseInsensitiveContains("tunnel")
                    || kind.localizedCaseInsensitiveContains("arch") {
                    updateProp(
                        key: "\(themeID)-\(index)-center-\(kind)",
                        kind: kind,
                        seed: seed,
                        distance: stationDistance,
                        lateral: 0,
                        yawOffset: 0,
                        mapper: mapper,
                        environment: environment,
                        activeKeys: &activeKeys,
                        newPropsRemaining: &newPropsRemaining
                    )
                } else {
                    for side in [-1.0, 1.0] {
                        let sideSeed = seed &+ (side < 0 ? 0x9E37_79B9 : 0x85EB_CA6B)
                        updateProp(
                            key: "\(themeID)-\(index)-\(side)-\(kind)",
                            kind: kind,
                            seed: sideSeed,
                            distance: stationDistance + (side < 0 ? spacing * 0.18 : spacing * 0.52),
                            lateral: side * (1.34 + Double(sideSeed % 9) * 0.025),
                            yawOffset: side < 0 ? .pi / 2 : -.pi / 2,
                            mapper: mapper,
                            environment: environment,
                            activeKeys: &activeKeys,
                            newPropsRemaining: &newPropsRemaining
                        )
                    }
                }
            }
        }

        for (key, node) in nodes.filter({ !activeKeys.contains($0.key) }).prefix(maximumRetiredPropsPerFrame) {
            node.removeFromParentNode()
            nodes[key] = nil
        }
    }

    private func updateProp(
        key: String,
        kind: String,
        seed: UInt64,
        distance: Double,
        lateral: Double,
        yawOffset: Float,
        mapper: TrackWorldMapper3D,
        environment: NeonEnvironment3D,
        activeKeys: inout Set<String>,
        newPropsRemaining: inout Int
    ) {
        let node: SCNNode
        if let existing = nodes[key] {
            node = existing
        } else {
            guard newPropsRemaining > 0 else { return }
            newPropsRemaining -= 1
            let made = environment.makeRoadsideProp(kind: kind, seed: seed)
            made.name = made.name ?? "roadside-prop-\(kind)"
            nodes[key] = made
            rootNode.addChildNode(made)
            node = made
        }
        activeKeys.insert(key)
        let frame = mapper.actorFrame(atRunDistance: distance, lateralPosition: lateral)
        node.position = frame.position
        node.eulerAngles = SCNVector3(frame.pitch, frame.yaw + yawOffset, 0)
        node.opacity = 1
    }

    private func removeAll() {
        for node in nodes.values {
            node.removeFromParentNode()
        }
        nodes.removeAll(keepingCapacity: true)
    }

    func releaseRecreatableResources() {
        removeAll()
    }

    private static func seed(environmentID: String, index: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in environmentID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        hash ^= UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15
        return hash
    }
}

private extension String {
    var audioEnvironment: AudioEnvironment {
        if contains("city") { return .city }
        if contains("peak") || contains("mount") { return .tunnel }
        if contains("desert") { return .desert }
        return .coast
    }
}

#if DEBUG
private extension SCNNode {
    var nrRecursiveNodeCount: Int {
        1 + childNodes.reduce(0) { $0 + $1.nrRecursiveNodeCount }
    }

    var nrGeometryNodeCount: Int {
        (geometry == nil ? 0 : 1) + childNodes.reduce(0) { $0 + $1.nrGeometryNodeCount }
    }
}
#endif

/// Breaks the CADisplayLink -> target retain cycle.
@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var owner: RaceScene3D?

    init(owner: RaceScene3D) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let owner else {
            link.invalidate()
            return
        }
        owner.displayLinkDidTick(link)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
