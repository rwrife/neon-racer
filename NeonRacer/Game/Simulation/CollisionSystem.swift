import Foundation

struct CollisionSystem: Equatable, Sendable {
    struct ScoringSignal: Equatable, Sendable {
        let event: GameplayScoreEvent
        let cues: [RaceFeedbackCue]
        let timePenalty: TimeInterval

        init(
            event: GameplayScoreEvent,
            cues: [RaceFeedbackCue],
            timePenalty: TimeInterval = 0
        ) {
            self.event = event
            self.cues = cues
            self.timePenalty = timePenalty
        }
    }

    struct StepResult: Equatable, Sendable {
        var scoringSignals: [ScoringSignal] = []
    }

    private enum Tuning {
        static let playerHalfWidthMeters = 0.95
        static let carHalfLength = 2.2
        static let crashRecoveryDuration: TimeInterval = 1.2
        static let obstacleRecoveryDuration: TimeInterval = 1.35
        static let nearMissGapMeters = 0.82
        static let nearMissMinimumSpeedRatio = 0.58
        static let nearMissMinimumRelativeSpeed = 4.0
        static let obstacleCollisionIDMask: UInt64 = 0x0B57_0000_0000_0000
        static let wipeoutBaseDuration: TimeInterval = 1.7
        static let wipeoutSeverityDuration: TimeInterval = 0.6
    }

    mutating func update(
        state: inout RaceState,
        configuration: RaceConfiguration,
        trackLayout: TrackLayout,
        deltaTime: TimeInterval
    ) -> StepResult {
        var result = StepResult()
        let wasRecovering = state.vehicle.crashRecoveryRemaining > 0
            || state.vehicle.isWipingOut
            || state.vehicle.respawnShieldRemaining > 0

        let sample = trackLayout.sample(
            stageID: state.currentStageID,
            distanceInStage: state.currentStageDistance
        )
        let roadHalfWidth = max(sample.roadHalfWidth, 1)
        let playerHalfWidth = (Tuning.playerHalfWidthMeters / roadHalfWidth).clamped(to: 0.06...0.32)

        if !wasRecovering {
            if let collision = resolveTrafficCollision(
                state: &state,
                playerHalfWidth: playerHalfWidth,
                configuration: configuration
            ) {
                result.scoringSignals.append(collision)
                return result
            }
            if let collision = resolveObstacleCollision(
                state: &state,
                playerHalfWidth: playerHalfWidth,
                configuration: configuration
            ) {
                result.scoringSignals.append(collision)
                return result
            }
        }

        detectPassesAndNearMisses(
            state: &state,
            playerHalfWidth: playerHalfWidth,
            roadHalfWidth: roadHalfWidth,
            configuration: configuration,
            result: &result
        )
        return result
    }

    private func resolveTrafficCollision(
        state: inout RaceState,
        playerHalfWidth: Double,
        configuration: RaceConfiguration
    ) -> ScoringSignal? {
        guard let index = state.traffic.indices.first(where: { index in
            let vehicle = state.traffic[index]
            return intersects(
                distanceA: state.distance,
                lateralA: state.lateralPosition,
                halfLengthA: Tuning.carHalfLength,
                halfWidthA: playerHalfWidth,
                distanceB: vehicle.distance,
                lateralB: vehicle.lateralPosition,
                halfLengthB: halfLength(for: vehicle.kind),
                halfWidthB: vehicle.halfWidth
            )
        }) else { return nil }

        let vehicle = state.traffic[index]
        let relativeSpeed = abs(state.speed - vehicle.speed)
        let severity = ((relativeSpeed / max(configuration.maximumSpeed, 1))
            + overlapSeverity(playerLateral: state.lateralPosition,
                              playerHalfWidth: playerHalfWidth,
                              obstacleLateral: vehicle.lateralPosition,
                              obstacleHalfWidth: vehicle.halfWidth))
            .clamped(to: 0.15...1)
        applyCrashResponse(
            state: &state,
            obstacleLateral: vehicle.lateralPosition,
            slowdownRatio: 0.60,
            recoveryDuration: Tuning.crashRecoveryDuration,
            severity: severity
        )
        state.speed = min(state.speed, max(vehicle.speed * 0.92, configuration.maximumSpeed * 0.18))
        state.traffic[index].speed = max(0, min(vehicle.speed * 0.72, state.speed * 0.86))
        state.traffic[index].isBraking = true
        state.traffic[index].lateralPosition = (vehicle.lateralPosition
            - bumpDirection(playerLateral: state.lateralPosition, obstacleLateral: vehicle.lateralPosition) * 0.05)
            .clamped(to: -0.96...0.96)
        let timePenalty = applyTimePenalty(
            configuration.crashPenalties.trafficTimePenalty,
            state: &state
        )

        return ScoringSignal(
            event: .collision(id: vehicle.id, severity: severity),
            cues: [.crash],
            timePenalty: timePenalty
        )
    }

    private func resolveObstacleCollision(
        state: inout RaceState,
        playerHalfWidth: Double,
        configuration: RaceConfiguration
    ) -> ScoringSignal? {
        guard let index = state.obstacles.indices.first(where: { index in
            let obstacle = state.obstacles[index]
            guard !obstacle.isHit else { return false }
            return intersects(
                distanceA: state.distance,
                lateralA: state.lateralPosition,
                halfLengthA: Tuning.carHalfLength,
                halfWidthA: playerHalfWidth,
                distanceB: obstacle.distance,
                lateralB: obstacle.lateralPosition,
                halfLengthB: obstacleHalfLength(for: obstacle.kind),
                halfWidthB: obstacle.halfWidth
            )
        }) else { return nil }

        let obstacle = state.obstacles[index]
        let severity = (0.55 + overlapSeverity(
            playerLateral: state.lateralPosition,
            playerHalfWidth: playerHalfWidth,
            obstacleLateral: obstacle.lateralPosition,
            obstacleHalfWidth: obstacle.halfWidth
        ) * 0.45).clamped(to: 0.55...1)
        applyCrashResponse(
            state: &state,
            obstacleLateral: obstacle.lateralPosition,
            slowdownRatio: 0.44,
            recoveryDuration: Tuning.obstacleRecoveryDuration,
            severity: severity
        )
        state.obstacles[index].isHit = true
        let timePenalty = applyTimePenalty(
            timePenalty(for: obstacle, configuration: configuration),
            state: &state
        )

        return ScoringSignal(
            event: .collision(id: obstacle.id ^ Tuning.obstacleCollisionIDMask, severity: severity),
            cues: [.obstacleHit, .crash],
            timePenalty: timePenalty
        )
    }

    private func detectPassesAndNearMisses(
        state: inout RaceState,
        playerHalfWidth: Double,
        roadHalfWidth: Double,
        configuration: RaceConfiguration,
        result: inout StepResult
    ) {
        for index in state.traffic.indices where !state.traffic[index].hasBeenPassed {
            let vehicle = state.traffic[index]
            let passLine = vehicle.distance + halfLength(for: vehicle.kind)
            guard state.distance > passLine else { continue }

            let lateralGap = abs(state.lateralPosition - vehicle.lateralPosition)
                - playerHalfWidth
                - vehicle.halfWidth
            let gapMeters = lateralGap * roadHalfWidth
            let relativeSpeed = state.speed - vehicle.speed
            let isNearMiss = gapMeters > 0
                && gapMeters <= Tuning.nearMissGapMeters
                && state.speed >= configuration.maximumSpeed * Tuning.nearMissMinimumSpeedRatio
                && relativeSpeed >= Tuning.nearMissMinimumRelativeSpeed
            if isNearMiss {
                result.scoringSignals.append(ScoringSignal(
                    event: .nearMiss(
                        id: vehicle.id,
                        proximity: (gapMeters / Tuning.nearMissGapMeters).clamped(to: 0...1)
                    ),
                    cues: [.nearMiss]
                ))
            } else {
                result.scoringSignals.append(ScoringSignal(
                    event: .overtake(id: vehicle.id),
                    cues: [.overtake]
                ))
            }
            if vehicle.kind == .rival {
                result.scoringSignals.append(ScoringSignal(
                    event: .position(place: 1),
                    cues: []
                ))
            }
            state.traffic[index].hasBeenPassed = true
        }
    }

    private func applyCrashResponse(
        state: inout RaceState,
        obstacleLateral: Double,
        slowdownRatio: Double,
        recoveryDuration: TimeInterval,
        severity: Double
    ) {
        let direction = bumpDirection(
            playerLateral: state.lateralPosition,
            obstacleLateral: obstacleLateral
        )
        state.speed = max(0, state.speed * slowdownRatio)
        state.lateralPosition = (state.lateralPosition + direction * 0.11).clamped(to: -1...1)
        state.vehicle.roadPosition.heading = (state.vehicle.roadPosition.heading + direction * 0.18)
            .clamped(to: -1...1)
        state.vehicle.crashRecoveryRemaining = recoveryDuration
        state.vehicle.isDrifting = false
        let wipeoutDuration = Tuning.wipeoutBaseDuration + Tuning.wipeoutSeverityDuration * severity
        state.vehicle.wipeoutDuration = wipeoutDuration
        state.vehicle.wipeoutRemaining = wipeoutDuration
        state.vehicle.wipeoutDirection = direction
        state.vehicle.wipeoutSeverity = severity.clamped(to: 0...1)
        state.vehicle.respawnShieldRemaining = 0
    }

    private func intersects(
        distanceA: Double,
        lateralA: Double,
        halfLengthA: Double,
        halfWidthA: Double,
        distanceB: Double,
        lateralB: Double,
        halfLengthB: Double,
        halfWidthB: Double
    ) -> Bool {
        abs(distanceA - distanceB) <= halfLengthA + halfLengthB
            && abs(lateralA - lateralB) <= halfWidthA + halfWidthB
    }

    private func overlapSeverity(
        playerLateral: Double,
        playerHalfWidth: Double,
        obstacleLateral: Double,
        obstacleHalfWidth: Double
    ) -> Double {
        let overlap = playerHalfWidth + obstacleHalfWidth - abs(playerLateral - obstacleLateral)
        let total = max(playerHalfWidth + obstacleHalfWidth, 0.000_1)
        return (overlap / total).clamped(to: 0...1)
    }

    private func bumpDirection(playerLateral: Double, obstacleLateral: Double) -> Double {
        playerLateral >= obstacleLateral ? 1 : -1
    }

    private func halfLength(for kind: TrafficVehicleKind) -> Double {
        switch kind {
        case .commuter: 2.2
        case .hauler: 4.4
        case .rival: 2.3
        }
    }

    private func obstacleHalfLength(for kind: TrackObstacleKind) -> Double {
        switch kind {
        case .neonBarrier: 1.8
        case .pylon: 1.0
        case .laserGate: 2.4
        case .roadsideBillboardPost: 1.4
        case .neonPalmTrunk: 1.2
        case .holoSignPylon: 1.5
        case .debris: 1.0
        }
    }

    private func timePenalty(
        for obstacle: TrackObstacleState,
        configuration: RaceConfiguration
    ) -> TimeInterval {
        if isRoadsideHazard(obstacle) {
            return configuration.crashPenalties.roadsideHazardTimePenalty
        }
        return configuration.crashPenalties.obstacleTimePenalty
    }

    private func applyTimePenalty(_ seconds: TimeInterval, state: inout RaceState) -> TimeInterval {
        guard seconds.isFinite, seconds > 0, state.timerRemaining > 0 else { return 0 }
        let applied = min(state.timerRemaining, seconds)
        state.timerRemaining = max(0, state.timerRemaining - applied)
        state.lastTimePenalty = applied
        state.lastTimePenaltyTime = state.elapsedTime
        return applied
    }

    private func isRoadsideHazard(_ obstacle: TrackObstacleState) -> Bool {
        switch obstacle.kind {
        case .roadsideBillboardPost, .neonPalmTrunk, .holoSignPylon, .debris:
            return true
        case .neonBarrier, .pylon, .laserGate:
            return abs(obstacle.lateralPosition) > 1
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
