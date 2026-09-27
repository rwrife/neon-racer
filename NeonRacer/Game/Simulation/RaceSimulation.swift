import Foundation

enum RacePhase: String, Codable, Equatable, Sendable {
    case ready
    case running
    case paused
    case finished
    case failed
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
}

struct ScoreInputs: Codable, Equatable, Sendable {
    var distancePoints: Double = 0
    var boostTime: TimeInterval = 0
    var boostPoints: Double = 0

    var total: Double {
        distancePoints + boostPoints
    }
}

struct RaceState: Codable, Equatable, Sendable {
    var elapsedTime: TimeInterval = 0
    var vehicle = VehicleState()
    var timerRemaining: TimeInterval = 90
    var scoreInputs = ScoreInputs()
    var boostCharge: TimeInterval = 0
    var isBoostActive = false
    var stageProgress: Double = 0
    var trafficDensity: Double = 0
    var phase: RacePhase = .ready

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
    private(set) var diagnostics = SimulationDiagnostics()
    private var previousState: RaceState
    private var accumulatedTime: TimeInterval = 0
    private var randomNumberGenerator: SeededRandomNumberGenerator
    private var wasBoosting = false
    private let configuration: RaceConfiguration

    init(configuration: RaceConfiguration = .standard, seed: UInt64 = 1) {
        precondition(
            configuration.validationErrors.isEmpty,
            "Invalid race configuration: \(configuration.validationErrors)"
        )
        self.configuration = configuration
        state = RaceState(
            timerRemaining: configuration.raceDuration,
            boostCharge: configuration.boost.initialCharge
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
              state.phase != .failed else {
            diagnostics.lastStepCount = 0
            return
        }

        if state.phase == .ready {
            state.phase = .running
            events.append(.started(time: state.elapsedTime))
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
        case (true, .ready), (true, .running):
            state.phase = .paused
        case (false, .paused):
            state.phase = .running
        default:
            break
        }
    }

    mutating func finish() {
        guard state.phase == .running || state.phase == .paused else { return }
        state.phase = .finished
        events.append(.finished(time: state.elapsedTime))
        accumulatedTime = 0
    }

    mutating func fail() {
        guard state.phase == .running || state.phase == .paused else { return }
        state.phase = .failed
        events.append(.failed(time: state.elapsedTime))
        accumulatedTime = 0
    }

    mutating func restart(seed: UInt64 = 1) {
        state = RaceState(
            timerRemaining: configuration.raceDuration,
            boostCharge: configuration.boost.initialCharge
        )
        previousState = state
        accumulatedTime = 0
        events = []
        diagnostics = SimulationDiagnostics()
        randomNumberGenerator = SeededRandomNumberGenerator(seed: seed)
        wasBoosting = false
    }

    mutating func reset() {
        restart()
    }

    private mutating func update(command: PlayerCommand, deltaTime: TimeInterval) {
        let throttle = command.throttle.clamped(to: 0...1)
        let brake = command.brake.clamped(to: 0...1)
        let steering = command.steering.clamped(to: -1...1)
        let isBoostActive = command.isBoosting
            && throttle > brake
            && state.boostCharge > 0
        state.isBoostActive = isBoostActive
        if isBoostActive != wasBoosting {
            events.append(
                isBoostActive
                    ? .boostStarted(time: state.elapsedTime)
                    : .boostEnded(time: state.elapsedTime)
            )
            wasBoosting = isBoostActive
        }

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
        state.scoreInputs.distancePoints += distanceDelta * configuration.scoring.pointsPerDistance
        if isBoostActive {
            state.boostCharge = max(
                0,
                state.boostCharge - configuration.boost.consumptionPerSecond * deltaTime
            )
            state.scoreInputs.boostTime += deltaTime
            state.scoreInputs.boostPoints +=
                configuration.scoring.pointsPerBoostSecond * deltaTime
        } else if !command.isBoosting {
            state.boostCharge = min(
                configuration.boost.capacity,
                state.boostCharge + configuration.boost.rechargePerSecond * deltaTime
            )
        }
        state.stageProgress = min(state.distance / configuration.stageLength, 1)

        state.trafficDensity = configuration.traffic.density(
            progress: state.stageProgress,
            randomUnitValue: randomNumberGenerator.nextUnitDouble()
        )

        if state.stageProgress >= 1 {
            state.phase = .finished
            events.append(.finished(time: state.elapsedTime))
        } else if state.timerRemaining <= 0 {
            state.phase = .failed
            events.append(.failed(time: state.elapsedTime))
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
