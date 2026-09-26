import Foundation

enum RacePhase: String, Codable, Equatable, Sendable {
    case ready
    case running
    case paused
    case finished
    case failed
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

    var total: Double {
        distancePoints + boostTime * 25
    }
}

struct RaceState: Codable, Equatable, Sendable {
    var elapsedTime: TimeInterval = 0
    var vehicle = VehicleState()
    var timerRemaining: TimeInterval = 90
    var scoreInputs = ScoreInputs()
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
    private(set) var diagnostics = SimulationDiagnostics()
    private var previousState: RaceState
    private var accumulatedTime: TimeInterval = 0
    private var randomNumberGenerator: SeededRandomNumberGenerator
    private let configuration: RaceConfiguration

    init(configuration: RaceConfiguration = .standard, seed: UInt64 = 1) {
        self.configuration = configuration
        state = RaceState(timerRemaining: configuration.raceDuration)
        previousState = state
        randomNumberGenerator = SeededRandomNumberGenerator(seed: seed)
    }

    var renderSnapshot: RaceRenderSnapshot {
        RaceRenderSnapshot(
            previous: previousState,
            current: state,
            interpolationAlpha: min(max(accumulatedTime / configuration.fixedTimeStep, 0), 1)
        )
    }

    mutating func advance(frameDelta: TimeInterval, command: PlayerCommand) {
        guard state.phase != .paused,
              state.phase != .finished,
              state.phase != .failed else {
            diagnostics.lastStepCount = 0
            return
        }

        if state.phase == .ready {
            state.phase = .running
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
        accumulatedTime = 0
    }

    mutating func fail() {
        guard state.phase == .running || state.phase == .paused else { return }
        state.phase = .failed
        accumulatedTime = 0
    }

    mutating func restart(seed: UInt64 = 1) {
        state = RaceState(timerRemaining: configuration.raceDuration)
        previousState = state
        accumulatedTime = 0
        diagnostics = SimulationDiagnostics()
        randomNumberGenerator = SeededRandomNumberGenerator(seed: seed)
    }

    mutating func reset() {
        restart()
    }

    private mutating func update(command: PlayerCommand, deltaTime: TimeInterval) {
        let throttle = command.throttle.clamped(to: 0...1)
        let brake = command.brake.clamped(to: 0...1)
        let steering = command.steering.clamped(to: -1...1)

        let forwardForce = throttle * configuration.acceleration
        let brakingForce = brake * configuration.braking
        let dragForce = state.speed > 0 ? configuration.drag : 0

        state.speed += (forwardForce - brakingForce - dragForce) * deltaTime
        state.speed = state.speed.clamped(to: 0...configuration.maximumSpeed)

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
        state.scoreInputs.distancePoints += distanceDelta
        if command.isBoosting {
            state.scoreInputs.boostTime += deltaTime
        }
        state.stageProgress = min(state.distance / configuration.stageLength, 1)

        // Seeded variation keeps future traffic decisions replayable without global randomness.
        state.trafficDensity = 0.2 + randomNumberGenerator.nextUnitDouble() * 0.15

        if state.stageProgress >= 1 {
            state.phase = .finished
        } else if state.timerRemaining <= 0 {
            state.phase = .failed
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
