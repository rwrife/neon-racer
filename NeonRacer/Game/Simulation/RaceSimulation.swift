import Foundation

enum RaceOutcome: String, Codable, Equatable, Sendable {
    case finished
    case failed
}

struct RaceResult: Codable, Equatable, Sendable {
    let outcome: RaceOutcome
    let score: Int
    let distancePoints: Int
    let speedPoints: Int
    let boostPoints: Int
    let overtakePoints: Int
    let nearMissPoints: Int
    let driftPoints: Int
    let checkpointPoints: Int
    let positionPoints: Int
    let finishPoints: Int
    let collisionPoints: Int
    let rank: RaceRank
    let elapsedTime: TimeInterval
    let distance: Double
    let routeName: String
    let scoreBreakdown: [ScoreBreakdownEntry]

    init(
        state: RaceState,
        rank: RaceRank,
        routeName: String = "Neon Causeway",
        scoreBreakdown: [ScoreBreakdownEntry] = []
    ) {
        outcome = state.phase == .finished ? .finished : .failed
        score = Int(state.score.rounded())
        distancePoints = Int(state.scoreInputs.distancePoints.rounded())
        speedPoints = Int(state.scoreInputs.speedPoints.rounded())
        boostPoints = Int(state.scoreInputs.boostPoints.rounded())
        overtakePoints = Int(state.scoreInputs.overtakePoints.rounded())
        nearMissPoints = Int(state.scoreInputs.nearMissPoints.rounded())
        driftPoints = Int(state.scoreInputs.driftPoints.rounded())
        checkpointPoints = Int(state.scoreInputs.checkpointPoints.rounded())
        positionPoints = Int(state.scoreInputs.positionPoints.rounded())
        finishPoints = Int(state.scoreInputs.finishPoints.rounded())
        collisionPoints = Int(state.scoreInputs.collisionPoints.rounded())
        self.rank = rank
        elapsedTime = state.elapsedTime
        distance = state.distance
        self.routeName = routeName
        self.scoreBreakdown = scoreBreakdown
    }
}

enum RaceEvent: Codable, Equatable, Sendable {
    case started(time: TimeInterval)
    case boostStarted(time: TimeInterval)
    case boostEnded(time: TimeInterval)
    case finished(time: TimeInterval)
    case failed(time: TimeInterval)

    private enum CodingKeys: String, CodingKey {
        case kind = "k"
        case time = "t"
    }

    private enum Kind: String, Codable {
        case started = "s"
        case boostStarted = "bs"
        case boostEnded = "be"
        case finished = "f"
        case failed = "x"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let time = try container.decode(TimeInterval.self, forKey: .time)
        guard time.isFinite, time >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .time,
                in: container,
                debugDescription: "Event time must be finite and nonnegative."
            )
        }

        switch kind {
        case .started: self = .started(time: time)
        case .boostStarted: self = .boostStarted(time: time)
        case .boostEnded: self = .boostEnded(time: time)
        case .finished: self = .finished(time: time)
        case .failed: self = .failed(time: time)
        }
    }

    func encode(to encoder: Encoder) throws {
        let kind: Kind
        let time: TimeInterval
        switch self {
        case .started(let value):
            (kind, time) = (.started, value)
        case .boostStarted(let value):
            (kind, time) = (.boostStarted, value)
        case .boostEnded(let value):
            (kind, time) = (.boostEnded, value)
        case .finished(let value):
            (kind, time) = (.finished, value)
        case .failed(let value):
            (kind, time) = (.failed, value)
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(time, forKey: .time)
    }
}

struct RoadPosition: Codable, Equatable, Sendable {
    var distance: Double = 0
    var lateralOffset: Double = 0
    var heading: Double = 0
}

struct VehicleState: Codable, Equatable, Sendable {
    var roadPosition = RoadPosition()
    var speed: Double = 0
    /// Visual/physical slide angle in radians; positive slides the tail to the left.
    var slipAngle: Double = 0
    var isDrifting = false
    var isOffRoad = false
    /// Remaining seconds of post-crash recovery (reduced control, invulnerability).
    var crashRecoveryRemaining: TimeInterval = 0
}

struct ScoreInputs: Codable, Equatable, Sendable {
    var distancePoints: Double = 0
    var speedPoints: Double = 0
    var boostTime: TimeInterval = 0
    var boostPoints: Double = 0
    var overtakePoints: Double = 0
    var nearMissPoints: Double = 0
    var driftPoints: Double = 0
    var checkpointPoints: Double = 0
    var positionPoints: Double = 0
    var finishPoints: Double = 0
    var collisionPoints: Double = 0

    var total: Double {
        distancePoints + speedPoints + boostPoints + overtakePoints
            + nearMissPoints + driftPoints + checkpointPoints + positionPoints
            + finishPoints + collisionPoints
    }
}

struct RaceState: Codable, Equatable, Sendable {
    var elapsedTime: TimeInterval = 0
    var vehicle = VehicleState()
    var timerRemaining: TimeInterval = 90
    var scoreInputs = ScoreInputs()
    var boostCharge: TimeInterval = 0
    var isBoostActive = false
    var boostState: BoostState = .unavailable
    var combo = ComboState()
    var stageProgress: Double = 0
    var trafficDensity: Double = 0
    var phase: RacePhase = .loading
    var countdownRemaining: TimeInterval = 3
    var currentStageID: String = ""
    var currentStageDistance: Double = 0
    var currentEnvironmentID: String = ""
    var completedStageIDs: [String] = []
    var committedBranchIDs: [String] = []
    var traffic: [TrafficVehicleState] = []
    var obstacles: [TrackObstacleState] = []

    var distance: Double {
        get { vehicle.roadPosition.distance }
        set { vehicle.roadPosition.distance = newValue }
    }

    var speed: Double {
        get { vehicle.speed }
        set { vehicle.speed = newValue }
    }

    var lateralPosition: Double {
        get { vehicle.roadPosition.lateralOffset }
        set { vehicle.roadPosition.lateralOffset = newValue }
    }

    var score: Double {
        scoreInputs.total
    }
}

struct RaceRenderSnapshot: Equatable, Sendable {
    let previous: RaceState
    let current: RaceState
    let interpolationAlpha: Double
}

struct SimulationDiagnostics: Equatable, Sendable {
    var lastStepCount: Int = 0
    var droppedSimulationTime: TimeInterval = 0
}

struct SeededRandomNumberGenerator: RandomNumberGenerator, Equatable, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextUnitDouble() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }
}

struct RaceSimulation: Sendable {
    private(set) var state: RaceState
    private(set) var events: [RaceEvent] = []
    private(set) var scoreEvents: [ScoreEvent] = []
    private(set) var feedbackEvents: [RaceFeedbackEvent] = []
    private(set) var runEvents: [RunEvent] = []
    private(set) var diagnostics = SimulationDiagnostics()
    private var previousState: RaceState
    private var accumulatedTime: TimeInterval = 0
    private var randomNumberGenerator: SeededRandomNumberGenerator
    private var wasBoosting = false
    var processedActionIDs: [ScoreSource: Set<UInt64>] = [:]
    var processedPassIDs: Set<UInt64> = []
    var processedCollisionIDs: Set<UInt64> = []
    var lastActionTimes: [ScoreSource: TimeInterval] = [:]
    var lastAwardedPosition: Int?
    var didAwardFinish = false
    var boostCooldownRemaining: TimeInterval = 0
    let configuration: RaceConfiguration
    private let routeGraph: RouteGraph
    /// Deterministic road shape (curves, hills, lanes, start/finish zones) for the active route.
    let trackLayout: TrackLayout
    private let countdownDuration: TimeInterval
    private var stageStartDistance: Double = 0
    private var phaseBeforePause: RacePhase?
    private var hasPresentedCurrentFork = false

    init(
        configuration: RaceConfiguration = .standard,
        seed: UInt64 = 1,
        routeGraph: RouteGraph? = nil,
        countdownDuration: TimeInterval = 3
    ) {
        precondition(
            configuration.validationErrors.isEmpty,
            "Invalid race configuration: \(configuration.validationErrors)"
        )
        let resolvedRoute = routeGraph
            ?? (configuration.stageLength >= 1_000
                ? .neonForkFixture(totalDistance: configuration.stageLength)
                : .linearFixture(distance: configuration.stageLength))
        let routeErrors = resolvedRoute.validationErrors(
            maximumVehicleSpeed:
                configuration.maximumSpeed * configuration.boost.maximumSpeedMultiplier
        )
        precondition(routeErrors.isEmpty, "Invalid route graph: \(routeErrors)")
        precondition(countdownDuration.isFinite && countdownDuration >= 0)
        self.configuration = configuration
        self.routeGraph = resolvedRoute
        self.trackLayout = TrackLayout.forRoute(resolvedRoute)
        self.countdownDuration = countdownDuration
        let startStage = resolvedRoute.stage(id: resolvedRoute.startStageID)!
        state = RaceState(
            timerRemaining: configuration.raceDuration,
            boostCharge: configuration.boost.initialCharge,
            boostState: .unavailable,
            trafficDensity: configuration.traffic.baseDensity,
            countdownRemaining: countdownDuration,
            currentStageID: startStage.id,
            currentEnvironmentID: startStage.environmentID
        )
        previousState = state
        randomNumberGenerator = SeededRandomNumberGenerator(seed: seed)
    }

    var currentRank: RaceRank {
        configuration.scoring.rank(for: state.score)
    }

    var renderSnapshot: RaceRenderSnapshot {
        RaceRenderSnapshot(
            previous: previousState,
            current: state,
            interpolationAlpha: min(max(accumulatedTime / configuration.fixedTimeStep, 0), 1)
        )
    }

    mutating func advance(frameDelta: TimeInterval, command: PlayerCommand) {
        let interval = PerformanceInstrumentation.begin(.simulation)
        defer { PerformanceInstrumentation.end(.simulation, interval) }

        guard state.phase != .paused,
              state.phase != .finished,
              state.phase != .failed,
              state.phase != .restarting else {
            diagnostics.lastStepCount = 0
            return
        }

        let nonnegativeDelta = max(frameDelta, 0)
        let clampedDelta = min(nonnegativeDelta, configuration.maximumFrameDelta)
        diagnostics.droppedSimulationTime += nonnegativeDelta - clampedDelta
        accumulatedTime += clampedDelta

        var stepCount = 0
        let comparisonEpsilon = configuration.fixedTimeStep * 0.000_001
        while accumulatedTime + comparisonEpsilon >= configuration.fixedTimeStep,
              stepCount < configuration.maximumSimulationStepsPerFrame {
            previousState = state
            update(command: command, deltaTime: configuration.fixedTimeStep)
            accumulatedTime = max(0, accumulatedTime - configuration.fixedTimeStep)
            stepCount += 1
            if state.phase == .finished || state.phase == .failed {
                accumulatedTime = 0
                break
            }
        }

        if stepCount == configuration.maximumSimulationStepsPerFrame,
           accumulatedTime + comparisonEpsilon >= configuration.fixedTimeStep {
            diagnostics.droppedSimulationTime += accumulatedTime
            accumulatedTime = 0
        }
        diagnostics.lastStepCount = stepCount
    }

    mutating func setPaused(_ paused: Bool) {
        switch (paused, state.phase) {
        case (true, .loading), (true, .countdown), (true, .racing),
             (true, .checkpoint), (true, .fork):
            phaseBeforePause = state.phase
            state.phase = .paused
            runEvents.append(.paused(time: state.elapsedTime))
        case (false, .paused):
            state.phase = phaseBeforePause ?? .racing
            phaseBeforePause = nil
            runEvents.append(.resumed(time: state.elapsedTime))
        default:
            break
        }
    }

    mutating func finish() {
        guard ![.finished, .failed, .restarting].contains(state.phase) else { return }
        ingest(.finish(position: nil))
        state.phase = .finished
        events.append(.finished(time: state.elapsedTime))
        runEvents.append(.finished(time: state.elapsedTime, route: state.completedStageIDs))
        accumulatedTime = 0
    }

    mutating func fail() {
        guard ![.finished, .failed, .restarting].contains(state.phase) else { return }
        state.phase = .failed
        events.append(.failed(time: state.elapsedTime))
        runEvents.append(.failed(time: state.elapsedTime, stageID: state.currentStageID))
        accumulatedTime = 0
    }

    mutating func beginRestart() {
        guard state.phase != .restarting else { return }
        state.phase = .restarting
        runEvents.append(.restartRequested(time: state.elapsedTime))
        accumulatedTime = 0
    }

    mutating func completeRestart(seed: UInt64 = 1) {
        guard state.phase == .restarting else { return }
        resetRun(seed: seed)
    }

    mutating func restart(seed: UInt64 = 1) {
        beginRestart()
        completeRestart(seed: seed)
    }

    private mutating func resetRun(seed: UInt64) {
        let startStage = routeGraph.stage(id: routeGraph.startStageID)!
        state = RaceState(
            timerRemaining: configuration.raceDuration,
            boostCharge: configuration.boost.initialCharge,
            boostState: .unavailable,
            trafficDensity: configuration.traffic.baseDensity,
            countdownRemaining: countdownDuration,
            currentStageID: startStage.id,
            currentEnvironmentID: startStage.environmentID
        )
        previousState = state
        accumulatedTime = 0
        events = []
        scoreEvents = []
        feedbackEvents = []
        runEvents = []
        diagnostics = SimulationDiagnostics()
        randomNumberGenerator = SeededRandomNumberGenerator(seed: seed)
        wasBoosting = false
        processedActionIDs = [:]
        processedPassIDs = []
        processedCollisionIDs = []
        lastActionTimes = [:]
        lastAwardedPosition = nil
        didAwardFinish = false
        boostCooldownRemaining = 0
        stageStartDistance = 0
        phaseBeforePause = nil
        hasPresentedCurrentFork = false
    }

    mutating func reset() {
        restart()
    }

    private mutating func update(command: PlayerCommand, deltaTime: TimeInterval) {
        switch state.phase {
        case .loading:
            state.phase = .countdown
            runEvents.append(.loadingCompleted(time: state.elapsedTime))
            runEvents.append(
                .countdownStarted(time: state.elapsedTime, duration: countdownDuration)
            )
            if countdownDuration == 0 {
                startRace()
            } else {
                return
            }
        case .countdown:
            state.countdownRemaining = max(0, state.countdownRemaining - deltaTime)
            if state.countdownRemaining == 0 {
                startRace()
            }
            return
        case .checkpoint:
            state.phase = .racing
        case .racing, .fork:
            break
        case .paused, .finished, .failed, .restarting:
            return
        }

        let throttle = command.throttle.clamped(to: 0...1)
        let brake = command.brake.clamped(to: 0...1)
        let steering = command.steering.clamped(to: -1...1)
        boostCooldownRemaining = max(0, boostCooldownRemaining - deltaTime)
        let wantsBoost = command.isBoosting && throttle > brake && boostCooldownRemaining == 0
        var isBoostActive = wantsBoost && state.boostCharge > 0 && wasBoosting
        if wantsBoost && !wasBoosting
            && state.boostCharge >= configuration.arcadeScoring.activationCost {
            state.boostCharge -= configuration.arcadeScoring.activationCost
            isBoostActive = true
        }
        state.isBoostActive = isBoostActive
        if isBoostActive && !wasBoosting {
            transitionBoost(to: .starting)
            events.append(
                .boostStarted(time: state.elapsedTime)
            )
        } else if isBoostActive && state.boostState == .starting {
            transitionBoost(to: .active)
        } else if !isBoostActive && wasBoosting {
            transitionBoost(to: .ending)
            events.append(.boostEnded(time: state.elapsedTime))
        } else if !isBoostActive && state.boostState == .ending {
            transitionBoost(to: .unavailable)
        } else if command.isBoosting && !isBoostActive && state.boostState != .ending {
            transitionBoost(to: .unavailable)
        }
        wasBoosting = isBoostActive

        let boostAcceleration = isBoostActive ? configuration.boost.accelerationBonus : 0
        let forwardForce = throttle * configuration.acceleration + boostAcceleration
        let brakingForce = brake * configuration.braking
        let dragForce = state.speed > 0 ? configuration.drag : 0
        let speedLimit = configuration.maximumSpeed
            * (isBoostActive ? configuration.boost.maximumSpeedMultiplier : 1)

        state.speed += (forwardForce - brakingForce - dragForce) * deltaTime
        state.speed = state.speed.clamped(to: 0...speedLimit)

        let steeringAuthority = state.speed / configuration.maximumSpeed
        state.lateralPosition += steering
            * configuration.steeringRate
            * steeringAuthority
            * deltaTime
        state.lateralPosition = state.lateralPosition.clamped(to: -1...1)
        state.vehicle.roadPosition.heading = steering * steeringAuthority

        let distanceDelta = state.speed * deltaTime
        state.distance += distanceDelta
        state.elapsedTime += deltaTime
        state.timerRemaining = max(0, state.timerRemaining - deltaTime)
        award(
            source: .distance,
            basePoints: distanceDelta * configuration.scoring.pointsPerDistance
        )
        let speedThreshold =
            configuration.maximumSpeed * configuration.arcadeScoring.highSpeedThresholdRatio
        if state.speed > speedThreshold {
            let speedRatio = (state.speed - speedThreshold)
                / (configuration.maximumSpeed * configuration.boost.maximumSpeedMultiplier - speedThreshold)
            award(
                source: .speed,
                basePoints: configuration.arcadeScoring.highSpeedPointsPerSecond
                    * speedRatio * deltaTime
            )
        }
        if isBoostActive {
            state.boostCharge = max(
                0,
                state.boostCharge - configuration.boost.consumptionPerSecond * deltaTime
            )
            state.scoreInputs.boostTime += deltaTime
            award(
                source: .boost,
                basePoints: configuration.scoring.pointsPerBoostSecond * deltaTime
            )
        } else if !command.isBoosting {
            state.boostCharge = min(
                configuration.boost.capacity,
                state.boostCharge + configuration.boost.rechargePerSecond * deltaTime
            )
        }
        updateCombo(deltaTime: deltaTime)
        guard let currentStage = routeGraph.stage(id: state.currentStageID) else {
            preconditionFailure("Current route stage '\(state.currentStageID)' is missing")
        }
        state.currentStageDistance = max(0, state.distance - stageStartDistance)
        state.stageProgress = min(state.currentStageDistance / currentStage.distance, 1)

        state.trafficDensity = configuration.traffic.density(
            progress: state.stageProgress,
            randomUnitValue: randomNumberGenerator.nextUnitDouble()
        )

        let distanceRemaining = max(0, currentStage.distance - state.currentStageDistance)
        if currentStage.branches.count > 1,
           distanceRemaining <= routeGraph.forkDecisionDistance,
           !hasPresentedCurrentFork {
            hasPresentedCurrentFork = true
            state.phase = .fork
            runEvents.append(
                .forkPresented(
                    time: state.elapsedTime,
                    stageID: currentStage.id,
                    branches: currentStage.branches
                )
            )
        }

        if state.timerRemaining <= 0 {
            state.phase = .failed
            events.append(.failed(time: state.elapsedTime))
            runEvents.append(.failed(time: state.elapsedTime, stageID: state.currentStageID))
        } else if state.stageProgress >= 1 {
            complete(currentStage)
        }
    }

    mutating func acceptUnique(
            _ id: UInt64,
            source: ScoreSource,
            cooldown: TimeInterval
        ) -> Bool {
            guard processedActionIDs[source, default: []].insert(id).inserted else { return false }
            if let lastTime = lastActionTimes[source],
               state.elapsedTime - lastTime < cooldown {
                return false
            }
            lastActionTimes[source] = state.elapsedTime
            return true
        }

        mutating func acceptPass(
            _ id: UInt64,
            source: ScoreSource,
            cooldown: TimeInterval
        ) -> Bool {
            guard processedPassIDs.insert(id).inserted else { return false }
            return acceptUnique(id, source: source, cooldown: cooldown)
        }

    mutating func awardSkill(
            source: ScoreSource,
            basePoints: Double,
            boostEarned: TimeInterval
        ) {
            state.combo.chainCount += 1
            state.combo.multiplier = min(4, 1 + Double(state.combo.chainCount / 2) * 0.25)
            state.combo.timeSinceSkill = 0
            state.combo.slowDrivingTime = 0
            award(source: source, basePoints: basePoints, multiplier: state.combo.multiplier)
            let oldCharge = state.boostCharge
            state.boostCharge = min(configuration.boost.capacity, state.boostCharge + boostEarned)
            if state.boostCharge > oldCharge {
                feedbackEvents.append(.init(
                    time: state.elapsedTime,
                    cue: .boostEarned,
                    channels: [.hud, .audio, .particle]
                ))
            }
            feedbackEvents.append(.init(
                time: state.elapsedTime,
                cue: .comboIncreased,
                channels: [.hud, .audio, .particle, .haptic]
            ))
        }

    mutating func award(
            source: ScoreSource,
            basePoints: Double,
            multiplier: Double = 1
        ) {
            guard basePoints.isFinite, basePoints != 0 else { return }
            let previousRank = currentRank
            let points = basePoints * multiplier
            state.scoreInputs.add(points, source: source)
            let scoreEvent = ScoreEvent(
                sequence: scoreEvents.count,
                time: state.elapsedTime,
                source: source,
                basePoints: basePoints,
                multiplier: multiplier,
                points: points,
                totalAfter: state.score
            )
            scoreEvents.append(scoreEvent)
            feedbackEvents.append(.init(
                time: state.elapsedTime,
                cue: .scoreAwarded,
                channels: [.hud]
            ))
            if currentRank != previousRank {
                feedbackEvents.append(.init(
                    time: state.elapsedTime,
                    cue: .rankChanged,
                    channels: [.hud, .audio, .particle, .haptic]
                ))
            }
        }

    mutating func updateCombo(deltaTime: TimeInterval) {
            guard state.combo.chainCount > 0 else { return }
            state.combo.timeSinceSkill += deltaTime
            if state.speed < configuration.maximumSpeed * 0.2 {
                state.combo.slowDrivingTime += deltaTime
            } else {
                state.combo.slowDrivingTime = 0
            }
            if state.combo.slowDrivingTime >= 3 {
                breakCombo(cue: .comboBroken)
            } else if state.combo.timeSinceSkill >= 3 {
                state.combo.chainCount = max(0, state.combo.chainCount - 1)
                state.combo.multiplier = min(4, 1 + Double(state.combo.chainCount / 2) * 0.25)
                state.combo.timeSinceSkill = 2
                feedbackEvents.append(.init(
                    time: state.elapsedTime,
                    cue: .comboDecayed,
                    channels: [.hud, .audio]
                ))
            }
        }

    mutating func breakCombo(cue: RaceFeedbackCue) {
            guard state.combo.chainCount > 0 else { return }
            state.combo = ComboState()
            feedbackEvents.append(.init(
                time: state.elapsedTime,
                cue: cue,
                channels: [.hud, .audio, .particle, .haptic]
            ))
        }

        mutating func handleCollision(id: UInt64, severity: Double) {
            guard severity.isFinite, processedCollisionIDs.insert(id).inserted else { return }
            let penalty = -(
                configuration.arcadeScoring.collisionPenalty
                    + configuration.arcadeScoring.collisionSeverityPenalty
                        * severity.clamped(to: 0...1)
            )
            award(source: .collision, basePoints: penalty)
            breakCombo(cue: .comboBroken)
            state.boostCharge = max(
                0,
                state.boostCharge - configuration.arcadeScoring.collisionBoostLoss
            )
            boostCooldownRemaining = max(
                boostCooldownRemaining,
                configuration.arcadeScoring.collisionBoostCooldown
            )
            if wasBoosting {
                events.append(.boostEnded(time: state.elapsedTime))
            }
            wasBoosting = false
            state.isBoostActive = false
            transitionBoost(to: .ending)
            feedbackEvents.append(.init(
                time: state.elapsedTime,
                cue: .collisionPenalty,
                channels: [.hud, .audio, .particle, .haptic]
            ))
        }

        mutating func transitionBoost(to newState: BoostState) {
            guard state.boostState != newState else { return }
            state.boostState = newState
            let cue: RaceFeedbackCue
            switch newState {
            case .unavailable: cue = .boostUnavailable
            case .starting: cue = .boostStarting
            case .active: cue = .boostActive
            case .ending: cue = .boostEnding
            }
            feedbackEvents.append(.init(
                time: state.elapsedTime,
                cue: cue,
                channels: [.hud, .audio, .particle, .haptic]
            ))
    }

    private mutating func startRace() {
        state.phase = .racing
        events.append(.started(time: state.elapsedTime))
        runEvents.append(.raceStarted(time: state.elapsedTime))
    }

    private mutating func complete(_ stage: RouteStage) {
        guard !stage.branches.isEmpty else {
            ingest(.finish(position: nil))
            state.phase = .finished
            events.append(.finished(time: state.elapsedTime))
            runEvents.append(
                .finished(
                    time: state.elapsedTime,
                    route: state.completedStageIDs + [stage.id]
                )
            )
            return
        }

        let branch: RouteBranch
        if stage.branches.count == 1 {
            branch = stage.branches[0]
        } else {
            let direction: RouteDirection = state.lateralPosition < 0 ? .left : .right
            branch = stage.branches.first { $0.direction == direction } ?? stage.branches[0]
            state.committedBranchIDs.append(branch.id)
            runEvents.append(
                .branchCommitted(time: state.elapsedTime, stageID: stage.id, branch: branch)
            )
        }

        guard let nextStage = routeGraph.stage(id: branch.destinationStageID) else {
            preconditionFailure(
                "Route branch '\(branch.id)' links to missing stage '\(branch.destinationStageID)'"
            )
        }
        state.completedStageIDs.append(stage.id)
        if stage.checkpointTimeAward > 0 {
            ingest(
                .checkpoint(
                    id: stableScoreEventID(stage.id),
                    secondsUnderPar: 0
                )
            )
        }
        state.timerRemaining += stage.checkpointTimeAward
        runEvents.append(
            .checkpointCrossed(
                time: state.elapsedTime,
                completedStageID: stage.id,
                nextStageID: nextStage.id,
                timeAward: stage.checkpointTimeAward
            )
        )
        stageStartDistance += stage.distance
        state.currentStageID = nextStage.id
        state.currentStageDistance = max(0, state.distance - stageStartDistance)
        state.currentEnvironmentID = nextStage.environmentID
        state.stageProgress = min(state.currentStageDistance / nextStage.distance, 1)
        state.phase = .checkpoint
        hasPresentedCurrentFork = false
        runEvents.append(
            .stageChanged(
                time: state.elapsedTime,
                stageID: nextStage.id,
                environmentID: nextStage.environmentID
            )
        )
    }

    private func stableScoreEventID(_ value: String) -> UInt64 {
        value.utf8.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
