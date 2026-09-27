import Foundation

struct DrivingModel: Sendable {
    struct RuntimeState: Equatable, Sendable {
        var activeDriftID: UInt64?
        var nextDriftID: UInt64 = 1
        var driftDuration: TimeInterval = 0
        var driftPeakIntensity: Double = 0
        var wasBraking = false
    }

    struct DriftAward: Equatable, Sendable {
        let id: UInt64
        let duration: TimeInterval
        let intensity: Double
    }

    struct Update: Equatable, Sendable {
        let vehicle: VehicleState
        let distanceDelta: Double
        let completedDrift: DriftAward?
    }

    static func update(
        vehicle: VehicleState,
        command: PlayerCommand,
        trackSample: TrackSample,
        configuration: RaceConfiguration,
        isBoostActive: Bool,
        deltaTime: TimeInterval,
        runtime: inout RuntimeState
    ) -> Update {
        let deltaTime = deltaTime.finiteOrZero.clamped(to: 0...configuration.maximumFrameDelta)
        guard deltaTime > 0 else {
            return Update(vehicle: vehicle, distanceDelta: 0, completedDrift: nil)
        }

        let driving = configuration.driving
        let shoulderFraction = trackSample.roadHalfWidth > 0
            ? max(0, trackSample.shoulderWidth / trackSample.roadHalfWidth)
            : 0
        let offRoadThreshold = 1 + shoulderFraction
        let initialOffRoad = abs(vehicle.roadPosition.lateralOffset) > offRoadThreshold

        let throttle = command.throttle.finiteOrZero.clamped(to: 0...1)
        let brake = command.brake.finiteOrZero.clamped(to: 0...1)
        let steering = command.steering.finiteOrZero.clamped(to: -1...1)
        let speedLimit = configuration.maximumSpeed
            * (isBoostActive ? configuration.boost.maximumSpeedMultiplier : 1)
        let boostAcceleration = isBoostActive ? configuration.boost.accelerationBonus : 0
        let gradeAcceleration = -trackSample.grade.finiteOrZero.clamped(to: -0.2...0.2)
            * driving.gradeAccelerationScale
        let surfaceDrag = initialOffRoad ? driving.offRoadDrag : 0
        let drag = vehicle.speed > 0 ? configuration.drag + surfaceDrag : 0

        var speed = vehicle.speed.finiteOrZero
        speed += (
            throttle * configuration.acceleration
            + boostAcceleration
            + gradeAcceleration
            - brake * configuration.braking
            - drag
        ) * deltaTime
        speed = speed.clamped(to: 0...speedLimit)

        let crashRecoveryRemaining = max(0, vehicle.crashRecoveryRemaining - deltaTime)
        let speedRatio = (speed / max(configuration.maximumSpeed, 0.000_001))
            .clamped(to: 0...configuration.boost.maximumSpeedMultiplier)
        let normalizedSpeedRatio = speedRatio.clamped(to: 0...1)
        let motionGate = (speed / 8).clamped(to: 0...1)
        let speedSensitiveAuthority =
            (driving.steeringAtRestRatio
                + (1 - driving.steeringAtRestRatio) * normalizedSpeedRatio)
            * motionGate
        let recoverySteeringScale = vehicle.crashRecoveryRemaining > 0
            ? driving.crashSteeringRatio
            : 1
        let gripScale = initialOffRoad ? driving.offRoadGripRatio : 1

        let driftUpdate = updateDrift(
            isCurrentlyDrifting: vehicle.isDrifting,
            steering: steering,
            brake: brake,
            speedRatio: normalizedSpeedRatio,
            curvature: trackSample.curvature.finiteOrZero,
            deltaTime: deltaTime,
            driving: driving,
            runtime: &runtime
        )

        let driftSteeringScale = driftUpdate.isDrifting
            ? driving.driftSteeringMultiplier
            : 1
        var lateral = vehicle.roadPosition.lateralOffset.finiteOrZero
        let steeringDelta = steering
            * configuration.steeringRate
            * speedSensitiveAuthority
            * recoverySteeringScale
            * gripScale
            * driftSteeringScale
        let centrifugalDelta = -trackSample.curvature.finiteOrZero
            * speed
            * speed
            * driving.centrifugalForce
            * deltaTime
        lateral += steeringDelta * deltaTime + centrifugalDelta

        var finalOffRoad = abs(lateral) > offRoadThreshold
        if finalOffRoad {
            let offRoadSpeedLimit = configuration.maximumSpeed
                * driving.offRoadSpeedLimitRatio
            speed = min(speed, max(offRoadSpeedLimit, speed - driving.offRoadDrag * deltaTime))
        }

        let lateralLimit = driving.lateralLimit
        if abs(lateral) > lateralLimit {
            lateral = lateral < 0 ? -lateralLimit : lateralLimit
            speed = max(0, speed - driving.wallSpeedLossPerSecond * deltaTime)
            finalOffRoad = abs(lateral) > offRoadThreshold
        }

        if driftUpdate.isDrifting {
            speed = max(0, speed - driving.driftSpeedLossPerSecond
                * driftUpdate.intensity * deltaTime)
        }

        let slipTarget = driftUpdate.isDrifting
            ? steering.signOrZero * driving.maximumDriftSlipAngle * driftUpdate.intensity
            : 0
        let slipStep = (driving.slipResponse * deltaTime).clamped(to: 0...1)
        let slipAngle = vehicle.slipAngle
            + (slipTarget - vehicle.slipAngle) * slipStep
        let steeringHeading = steering
            * speedSensitiveAuthority
            * driving.headingSteeringAngle
            * recoverySteeringScale
        let heading = (steeringHeading + slipAngle)
            .clamped(to: -driving.maximumDriftSlipAngle * 1.4...driving.maximumDriftSlipAngle * 1.4)

        var updatedVehicle = vehicle
        updatedVehicle.speed = speed
        updatedVehicle.roadPosition.lateralOffset = lateral
        updatedVehicle.roadPosition.heading = heading
        updatedVehicle.slipAngle = slipAngle
        updatedVehicle.isDrifting = driftUpdate.isDrifting
        updatedVehicle.isOffRoad = finalOffRoad
        updatedVehicle.crashRecoveryRemaining = crashRecoveryRemaining
        updatedVehicle.respawnShieldRemaining = max(0, vehicle.respawnShieldRemaining - deltaTime)

        return Update(
            vehicle: updatedVehicle,
            distanceDelta: speed * deltaTime,
            completedDrift: driftUpdate.completedDrift
        )
    }

    static let respawnShieldDuration: TimeInterval = 1.8

    /// Uncontrollable crash tumble: the car slides to a stop, then respawns stationary at the road
    /// center with a short invulnerability shield so the player can pull away again.
    static func updateWipeout(
        vehicle: VehicleState,
        configuration: RaceConfiguration,
        deltaTime: TimeInterval,
        runtime: inout RuntimeState
    ) -> Update {
        let deltaTime = deltaTime.finiteOrZero.clamped(to: 0...configuration.maximumFrameDelta)
        guard deltaTime > 0 else {
            return Update(vehicle: vehicle, distanceDelta: 0, completedDrift: nil)
        }
        var updated = vehicle
        let deceleration = max(configuration.braking * 1.25, vehicle.speed * 1.8)
        updated.speed = max(0, vehicle.speed - deceleration * deltaTime)
        let slideFade = vehicle.wipeoutDuration > 0
            ? (vehicle.wipeoutRemaining / vehicle.wipeoutDuration).clamped(to: 0...1)
            : 0
        updated.roadPosition.lateralOffset = (vehicle.roadPosition.lateralOffset
            + vehicle.wipeoutDirection * 0.55 * slideFade * deltaTime)
            .clamped(to: -configuration.driving.lateralLimit...configuration.driving.lateralLimit)
        updated.crashRecoveryRemaining = max(0, vehicle.crashRecoveryRemaining - deltaTime)
        updated.wipeoutRemaining = max(0, vehicle.wipeoutRemaining - deltaTime)
        updated.isDrifting = false
        updated.slipAngle = 0
        runtime.activeDriftID = nil
        runtime.driftDuration = 0
        runtime.driftPeakIntensity = 0

        if updated.wipeoutRemaining == 0 {
            updated.speed = 0
            updated.roadPosition.lateralOffset = 0
            updated.roadPosition.heading = 0
            updated.isOffRoad = false
            updated.crashRecoveryRemaining = 0
            updated.wipeoutDuration = 0
            updated.wipeoutDirection = 0
            updated.wipeoutSeverity = 0
            updated.respawnShieldRemaining = respawnShieldDuration
        }
        return Update(
            vehicle: updated,
            distanceDelta: updated.speed * deltaTime,
            completedDrift: nil
        )
    }

    private struct DriftUpdate {
        let isDrifting: Bool
        let intensity: Double
        let completedDrift: DriftAward?
    }

    private static func updateDrift(
        isCurrentlyDrifting: Bool,
        steering: Double,
        brake: Double,
        speedRatio: Double,
        curvature: Double,
        deltaTime: TimeInterval,
        driving: DrivingBalance,
        runtime: inout RuntimeState
    ) -> DriftUpdate {
        let hardSteer = abs(steering) >= driving.driftHardSteerThreshold
        let steeringIntoCurve = abs(curvature) >= driving.driftCurveThreshold
            && steering.signOrZero == curvature.signOrZero
        let brakeTap = brake >= driving.driftBrakeTapThreshold && !runtime.wasBraking
        runtime.wasBraking = brake >= driving.driftBrakeTapThreshold

        var isDrifting = isCurrentlyDrifting
        if !isDrifting,
           hardSteer,
           speedRatio >= driving.driftMinimumSpeedRatio,
           brakeTap || (steeringIntoCurve && speedRatio >= driving.driftCurveSpeedRatio) {
            runtime.activeDriftID = runtime.nextDriftID
            runtime.nextDriftID &+= 1
            runtime.driftDuration = 0
            runtime.driftPeakIntensity = 0
            isDrifting = true
        }

        var completedDrift: DriftAward?
        let shouldContinue = abs(steering) >= driving.driftExitSteerThreshold
            && speedRatio >= driving.driftMinimumSpeedRatio * 0.75
        if isDrifting, !shouldContinue {
            if let id = runtime.activeDriftID {
                completedDrift = DriftAward(
                    id: id,
                    duration: runtime.driftDuration,
                    intensity: runtime.driftPeakIntensity
                )
            }
            runtime.activeDriftID = nil
            runtime.driftDuration = 0
            runtime.driftPeakIntensity = 0
            isDrifting = false
        }

        let intensity = min(
            1,
            max(
                abs(steering),
                abs(curvature),
                speedRatio
            )
        )
        if isDrifting {
            runtime.driftDuration += deltaTime
            runtime.driftPeakIntensity = max(runtime.driftPeakIntensity, intensity)
        }

        return DriftUpdate(
            isDrifting: isDrifting,
            intensity: isDrifting ? intensity : 0,
            completedDrift: completedDrift
        )
    }
}

private extension Double {
    var finiteOrZero: Double { isFinite ? self : 0 }

    var signOrZero: Double {
        if self > 0 { return 1 }
        if self < 0 { return -1 }
        return 0
    }

    func clamped(to limits: ClosedRange<Double>) -> Double {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
