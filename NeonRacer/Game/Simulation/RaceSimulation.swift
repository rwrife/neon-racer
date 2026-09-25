import Foundation

struct RaceState: Equatable, Sendable {
    var elapsedTime: TimeInterval = 0
    var distance: Double = 0
    var speed: Double = 0
    var lateralPosition: Double = 0
}

struct RaceSimulation: Sendable {
    private(set) var state = RaceState()
    private var accumulatedTime: TimeInterval = 0
    private let configuration: RaceConfiguration

    init(configuration: RaceConfiguration = .standard) {
        self.configuration = configuration
    }

    mutating func advance(frameDelta: TimeInterval, command: PlayerCommand) {
        let clampedDelta = min(max(frameDelta, 0), configuration.maximumFrameDelta)
        accumulatedTime += clampedDelta

        var stepCount = 0
        while accumulatedTime >= configuration.fixedTimeStep,
              stepCount < configuration.maximumSimulationStepsPerFrame {
            update(command: command, deltaTime: configuration.fixedTimeStep)
            accumulatedTime -= configuration.fixedTimeStep
            stepCount += 1
        }

        if stepCount == configuration.maximumSimulationStepsPerFrame {
            accumulatedTime = 0
        }
    }

    mutating func reset() {
        state = RaceState()
        accumulatedTime = 0
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

        state.distance += state.speed * deltaTime
        state.elapsedTime += deltaTime
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

