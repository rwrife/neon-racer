import Foundation

struct TrafficSystem: Equatable, Sendable {
    private enum Tuning {
        static let minimumSpawnDistance = 250.0
        static let maximumSpawnDistance = 700.0
        static let despawnBehindDistance = 80.0
        static let despawnAheadDistance = 950.0
        static let finishSpawnBuffer = 150.0
        static let sameLaneSafetyBuffer = 36.0
        static let clusterHalfWindow = 58.0
    }

    private var randomNumberGenerator: SeededRandomNumberGenerator
    private var nextVehicleID: UInt64
    private var nextSpawnDistance: Double
    private var nextObstacleDistance: Double
    private var nextRoadsideObstacleDistance: Double

    init(seed: UInt64 = 1) {
        randomNumberGenerator = SeededRandomNumberGenerator(seed: seed ^ 0x54A6_FF1C_7A11_CE5D)
        nextVehicleID = 0x7000_0000_0000_0000
        nextSpawnDistance = TrackLayout.startGridLength + Tuning.minimumSpawnDistance
        nextObstacleDistance = TrackLayout.startGridLength + 420
        nextRoadsideObstacleDistance = TrackLayout.startGridLength + 360
    }

    mutating func reset(seed: UInt64) {
        self = TrafficSystem(seed: seed)
    }

    mutating func update(
        state: inout RaceState,
        configuration: RaceConfiguration,
        trackLayout: TrackLayout,
        currentStage: RouteStage,
        stageStartDistance: Double,
        deltaTime: TimeInterval
    ) {
        guard configuration.traffic.isEnabled else {
            state.traffic.removeAll()
            state.obstacles.removeAll()
            return
        }

        despawn(state: &state)
        updateVehicles(
            state: &state,
            configuration: configuration,
            trackLayout: trackLayout,
            deltaTime: deltaTime
        )
        spawnObstacles(
            state: &state,
            configuration: configuration,
            trackLayout: trackLayout,
            currentStage: currentStage,
            stageStartDistance: stageStartDistance
        )
        spawnVehicles(
            state: &state,
            configuration: configuration,
            trackLayout: trackLayout,
            currentStage: currentStage,
            stageStartDistance: stageStartDistance
        )
        despawn(state: &state)
    }

    private mutating func updateVehicles(
        state: inout RaceState,
        configuration: RaceConfiguration,
        trackLayout: TrackLayout,
        deltaTime: TimeInterval
    ) {
        let profile = runtimeProfile(
            stageID: state.currentStageID,
            environmentID: state.currentEnvironmentID,
            configuration: configuration
        )
        let trackProfile = trackLayout.profile(for: state.currentStageID)
        for index in state.traffic.indices {
            let oldLateral = state.traffic[index].lateralPosition
            let targetSpeed = targetSpeed(
                for: state.traffic[index],
                profile: profile,
                configuration: configuration,
                playerDistance: state.distance,
                playerSpeed: state.speed
            )
            let vehicleAhead = closestVehicleAhead(
                of: state.traffic[index],
                in: state.traffic,
                laneCount: trackProfile.laneCount
            )
            let shouldBrake = vehicleAhead.map { $0.distance - state.traffic[index].distance < 42 } ?? false
            let adjustedTarget = shouldBrake ? min(targetSpeed, max(0, vehicleAhead!.speed - 8)) : targetSpeed
            let acceleration = adjustedTarget > state.traffic[index].speed ? 7.5 : 18.0
            state.traffic[index].speed = approach(
                state.traffic[index].speed,
                adjustedTarget,
                maxDelta: acceleration * deltaTime
            )
            state.traffic[index].isBraking = shouldBrake || adjustedTarget < state.traffic[index].speed
            state.traffic[index].distance += state.traffic[index].speed * deltaTime

            let targetLane = desiredLane(
                for: state.traffic[index],
                playerLateral: state.lateralPosition,
                playerDistance: state.distance,
                laneCount: trackProfile.laneCount
            )
            let targetLateral = trackProfile.laneCenter(targetLane)
            let lateralRate = state.traffic[index].kind == .rival ? 0.56 : 0.22
            state.traffic[index].lateralPosition = approach(
                state.traffic[index].lateralPosition,
                targetLateral,
                maxDelta: lateralRate * deltaTime
            ).clamped(to: -0.96...0.96)
            let lateralDelta = state.traffic[index].lateralPosition - oldLateral
            state.traffic[index].steering = deltaTime > 0
                ? (lateralDelta / max(deltaTime, 0.000_1) / 0.7).clamped(to: -1...1)
                : 0
        }
    }

    private mutating func spawnVehicles(
        state: inout RaceState,
        configuration: RaceConfiguration,
        trackLayout: TrackLayout,
        currentStage: RouteStage,
        stageStartDistance: Double
    ) {
        let profile = runtimeProfile(
            stageID: currentStage.id,
            environmentID: state.currentEnvironmentID,
            configuration: configuration
        )
        let effectiveDensity = profile.effectiveDensity(
            simulationDensity: state.trafficDensity,
            configuration: configuration,
            progress: state.stageProgress
        )
        let targetCount = min(
            profile.maximumVehicles,
            max(0, Int((effectiveDensity * Double(profile.maximumVehicles)).rounded()))
        )
        guard state.traffic.count < targetCount else { return }

        let trackProfile = trackLayout.profile(for: currentStage.id)
        guard trackProfile.laneCount > 1 else { return }

        var attempts = 0
        while state.traffic.count < targetCount, attempts < 6 {
            attempts += 1
            let spawnWindow = safeSpawnWindow(
                state: state,
                trackLayout: trackLayout,
                stage: currentStage,
                stageStartDistance: stageStartDistance
            )
            guard let spawnWindow else { return }
            if nextSpawnDistance < spawnWindow.lowerBound {
                nextSpawnDistance = spawnWindow.lowerBound + randomUnit() * 70
            }
            guard nextSpawnDistance <= spawnWindow.upperBound else { return }

            let candidateDistance = nextSpawnDistance
            if let lane = chooseSafeLane(
                at: candidateDistance,
                state: state,
                trackLayout: trackLayout,
                stageID: currentStage.id,
                minimumHeadwayMeters: profile.minimumHeadwayMeters,
                reservedLane: nil
            ) {
                let kind = chooseVehicleKind(density: effectiveDensity)
                nextVehicleID &+= 1
                let speed = spawnSpeed(for: kind, profile: profile, configuration: configuration)
                state.traffic.append(TrafficVehicleState(
                    id: nextVehicleID,
                    kind: kind,
                    distance: candidateDistance,
                    lateralPosition: trackProfile.laneCenter(lane),
                    speed: speed,
                    halfWidth: halfWidth(for: kind, roadHalfWidth: trackProfile.roadHalfWidth)
                ))
                nextSpawnDistance = candidateDistance
                    + profile.minimumHeadwayMeters
                    + 24
                    + randomUnit() * 110
            } else {
                nextSpawnDistance = candidateDistance + 32 + randomUnit() * 64
            }
        }
    }

    private mutating func spawnObstacles(
        state: inout RaceState,
        configuration: RaceConfiguration,
        trackLayout: TrackLayout,
        currentStage: RouteStage,
        stageStartDistance: Double
    ) {
        let trackProfile = trackLayout.profile(for: currentStage.id)
        spawnRoadsideObstacle(
            state: &state,
            configuration: configuration,
            trackLayout: trackLayout,
            currentStage: currentStage,
            stageStartDistance: stageStartDistance
        )
        guard trackProfile.laneCount > 1 else { return }
        let spacing = (520 - 180 * state.stageProgress - 130 * configuration.traffic.maximumDensity)
            .clamped(to: 260...620)
        let lowerBound = max(
            state.distance + Tuning.minimumSpawnDistance,
            stageStartDistance + TrackLayout.startGridLength + 120
        )
        if nextObstacleDistance < lowerBound {
            nextObstacleDistance = lowerBound + randomUnit() * 140
        }

        guard let spawnWindow = safeSpawnWindow(
            state: state,
            trackLayout: trackLayout,
            stage: currentStage,
            stageStartDistance: stageStartDistance
        ), nextObstacleDistance <= spawnWindow.upperBound else { return }

        let candidateDistance = max(nextObstacleDistance, spawnWindow.lowerBound)
        guard candidateDistance <= spawnWindow.upperBound else { return }
        guard let lane = chooseSafeLane(
            at: candidateDistance,
            state: state,
            trackLayout: trackLayout,
            stageID: currentStage.id,
            minimumHeadwayMeters: 95,
            reservedLane: nil
        ) else {
            nextObstacleDistance = candidateDistance + 90
            return
        }

        let kind = chooseObstacleKind()
        let id = stableID("obstacle:\(currentStage.id):\(Int(candidateDistance / 5)):\(lane):\(kind.rawValue)")
        if !state.obstacles.contains(where: { $0.id == id }) {
            state.obstacles.append(TrackObstacleState(
                id: id,
                kind: kind,
                distance: candidateDistance,
                lateralPosition: trackProfile.laneCenter(lane),
                halfWidth: obstacleHalfWidth(for: kind, roadHalfWidth: trackProfile.roadHalfWidth)
            ))
        }
        nextObstacleDistance = candidateDistance + spacing + randomUnit() * 180
    }

    private mutating func spawnRoadsideObstacle(
        state: inout RaceState,
        configuration: RaceConfiguration,
        trackLayout: TrackLayout,
        currentStage: RouteStage,
        stageStartDistance: Double
    ) {
        let spacing = (460 - 120 * state.stageProgress - 80 * configuration.traffic.maximumDensity)
            .clamped(to: 300...620)
        let lowerBound = max(
            state.distance + Tuning.minimumSpawnDistance,
            stageStartDistance + TrackLayout.startGridLength + 90
        )
        if nextRoadsideObstacleDistance < lowerBound {
            nextRoadsideObstacleDistance = lowerBound + randomUnit() * 160
        }
        guard let spawnWindow = safeSpawnWindow(
            state: state,
            trackLayout: trackLayout,
            stage: currentStage,
            stageStartDistance: stageStartDistance
        ) else { return }
        let candidateDistance = max(nextRoadsideObstacleDistance, spawnWindow.lowerBound)
        guard candidateDistance <= spawnWindow.upperBound else { return }
        let kind = chooseRoadsideObstacleKind()
        let side = randomUnit() < 0.5 ? -1.0 : 1.0
        let lateral = side * (1.1 + randomUnit() * 0.35)
        let id = stableID("roadside:\(currentStage.id):\(Int(candidateDistance / 5)):\(side):\(kind.rawValue)")
        if !state.obstacles.contains(where: { $0.id == id }) {
            state.obstacles.append(TrackObstacleState(
                id: id,
                kind: kind,
                distance: candidateDistance,
                lateralPosition: lateral,
                halfWidth: roadsideObstacleHalfWidth(for: kind)
            ))
        }
        nextRoadsideObstacleDistance = candidateDistance + spacing + randomUnit() * 220
    }

    private func safeSpawnWindow(
        state: RaceState,
        trackLayout: TrackLayout,
        stage: RouteStage,
        stageStartDistance: Double
    ) -> ClosedRange<Double>? {
        let lowerBound = max(
            state.distance + Tuning.minimumSpawnDistance,
            stageStartDistance + TrackLayout.startGridLength + 1
        )
        let finalBuffer = trackLayout.isFinalStage(stage.id) ? Tuning.finishSpawnBuffer : 24
        let upperBound = min(
            state.distance + Tuning.maximumSpawnDistance,
            stageStartDistance + max(0, stage.distance - finalBuffer)
        )
        guard upperBound >= lowerBound else { return nil }
        return lowerBound...upperBound
    }

    private mutating func chooseSafeLane(
        at distance: Double,
        state: RaceState,
        trackLayout: TrackLayout,
        stageID: String,
        minimumHeadwayMeters: Double,
        reservedLane: Int?
    ) -> Int? {
        let profile = trackLayout.profile(for: stageID)
        let laneCount = profile.laneCount
        guard laneCount > 1 else { return nil }
        let sample = trackLayout.sample(stageID: stageID, distanceInStage: state.currentStageDistance)
        guard !sample.isStartZone, !sample.isFinishZone else { return nil }

        var lanes = Array(0..<laneCount)
        for index in lanes.indices.reversed() {
            let swap = Int(randomUnit() * Double(index + 1)).clamped(to: 0...index)
            lanes.swapAt(index, swap)
        }
        if let reservedLane {
            lanes.removeAll { $0 == reservedLane }
        }

        for lane in lanes where isLaneSafe(
            lane,
            at: distance,
            state: state,
            profile: profile,
            minimumHeadwayMeters: minimumHeadwayMeters
        ) && leavesEscapeLane(
            addingLane: lane,
            at: distance,
            state: state,
            profile: profile
        ) {
            return lane
        }
        return nil
    }

    private func isLaneSafe(
        _ lane: Int,
        at distance: Double,
        state: RaceState,
        profile: TrackSectionProfile,
        minimumHeadwayMeters: Double
    ) -> Bool {
        for vehicle in state.traffic {
            guard nearestLane(for: vehicle.lateralPosition, profile: profile) == lane else { continue }
            if abs(vehicle.distance - distance) < max(Tuning.sameLaneSafetyBuffer, minimumHeadwayMeters) {
                return false
            }
        }
        for obstacle in state.obstacles where !obstacle.isHit && abs(obstacle.lateralPosition) <= 1 {
            guard nearestLane(for: obstacle.lateralPosition, profile: profile) == lane else { continue }
            if abs(obstacle.distance - distance) < max(42, minimumHeadwayMeters * 0.6) {
                return false
            }
        }
        return true
    }

    private func leavesEscapeLane(
        addingLane: Int,
        at distance: Double,
        state: RaceState,
        profile: TrackSectionProfile
    ) -> Bool {
        var occupied: Set<Int> = [addingLane]
        for vehicle in state.traffic
        where abs(vehicle.distance - distance) <= Tuning.clusterHalfWindow {
            occupied.insert(nearestLane(for: vehicle.lateralPosition, profile: profile))
        }
        for obstacle in state.obstacles
        where !obstacle.isHit
            && abs(obstacle.lateralPosition) <= 1
            && abs(obstacle.distance - distance) <= Tuning.clusterHalfWindow {
            occupied.insert(nearestLane(for: obstacle.lateralPosition, profile: profile))
        }
        return occupied.count < profile.laneCount
    }

    private func despawn(state: inout RaceState) {
        let minimumDistance = state.distance - Tuning.despawnBehindDistance
        let maximumDistance = state.distance + Tuning.despawnAheadDistance
        state.traffic.removeAll {
            $0.distance < minimumDistance || $0.distance > maximumDistance
        }
        state.obstacles.removeAll {
            $0.distance < minimumDistance || $0.distance > maximumDistance
        }
    }

    private func runtimeProfile(
        stageID: String,
        environmentID: String,
        configuration: RaceConfiguration
    ) -> RuntimeTrafficProfile {
        if let authored = authoredTrafficProfile(stageID: stageID, environmentID: environmentID) {
            return authored
        }
        let density = configuration.traffic.baseDensity
        let maxVehicles = max(4, min(18, Int((8 + density * 20).rounded())))
        return RuntimeTrafficProfile(
            baseDensity: density,
            maximumVehicles: maxVehicles,
            minimumHeadwaySeconds: 1.8,
            speedRange: (configuration.maximumSpeed * 0.52)...(configuration.maximumSpeed * 0.78)
        )
    }

    private func authoredTrafficProfile(stageID: String, environmentID: String) -> RuntimeTrafficProfile? {
        let bundle = InitialRouteContent.bundle
        let themeID = bundle.themeID(for: stageID) ?? environmentID
        guard let zone = bundle.themeZones.first(where: { $0.id == themeID }),
              let profile = bundle.document.trafficProfiles.first(where: { $0.id == zone.trafficProfileID }) else {
            return nil
        }
        return RuntimeTrafficProfile(
            baseDensity: profile.baseDensity,
            maximumVehicles: profile.maximumVehicles,
            minimumHeadwaySeconds: profile.minimumHeadway,
            speedRange: profile.speedRange.lowerBound...profile.speedRange.upperBound
        )
    }

    private func targetSpeed(
        for vehicle: TrafficVehicleState,
        profile: RuntimeTrafficProfile,
        configuration: RaceConfiguration,
        playerDistance: Double,
        playerSpeed: Double
    ) -> Double {
        let unit = stableUnit(vehicle.id ^ 0xA53A_9E37)
        switch vehicle.kind {
        case .commuter:
            return (profile.speedRange.lowerBound
                + (profile.speedRange.upperBound - profile.speedRange.lowerBound) * unit)
                .clamped(to: 20...(configuration.maximumSpeed * 0.84))
        case .hauler:
            return (profile.speedRange.lowerBound * 0.84 + 7 * unit)
                .clamped(to: 18...(configuration.maximumSpeed * 0.7))
        case .rival:
            let relativeDistance = vehicle.distance - playerDistance
            let contestSpeed = max(profile.speedRange.upperBound, playerSpeed * (relativeDistance < 90 ? 0.96 : 1.03))
            return contestSpeed.clamped(to: configuration.maximumSpeed * 0.66...configuration.maximumSpeed * 0.97)
        }
    }

    private func spawnSpeed(
        for kind: TrafficVehicleKind,
        profile: RuntimeTrafficProfile,
        configuration: RaceConfiguration
    ) -> Double {
        let unit = randomNumberGeneratorPreviewUnit(nextVehicleID ^ UInt64(kind.rawValue.count))
        switch kind {
        case .commuter:
            return (profile.speedRange.lowerBound
                + (profile.speedRange.upperBound - profile.speedRange.lowerBound) * unit)
                .clamped(to: 18...(configuration.maximumSpeed * 0.82))
        case .hauler:
            return (profile.speedRange.lowerBound * 0.82 + 6 * unit)
                .clamped(to: 16...(configuration.maximumSpeed * 0.68))
        case .rival:
            return (configuration.maximumSpeed * (0.84 + unit * 0.11))
                .clamped(to: 26...(configuration.maximumSpeed * 0.97))
        }
    }

    private mutating func chooseVehicleKind(density: Double) -> TrafficVehicleKind {
        let unit = randomUnit()
        let rivalChance = (0.08 + density * 0.08).clamped(to: 0.08...0.18)
        let haulerChance = (0.18 + density * 0.12).clamped(to: 0.18...0.34)
        if unit < rivalChance { return .rival }
        if unit < rivalChance + haulerChance { return .hauler }
        return .commuter
    }

    private mutating func chooseObstacleKind() -> TrackObstacleKind {
        let unit = randomUnit()
        if unit < 0.42 { return .pylon }
        if unit < 0.77 { return .neonBarrier }
        return .laserGate
    }

    private mutating func chooseRoadsideObstacleKind() -> TrackObstacleKind {
        let unit = randomUnit()
        if unit < 0.28 { return .roadsideBillboardPost }
        if unit < 0.56 { return .neonPalmTrunk }
        if unit < 0.82 { return .holoSignPylon }
        return .debris
    }

    private func desiredLane(
        for vehicle: TrafficVehicleState,
        playerLateral: Double,
        playerDistance: Double,
        laneCount: Int
    ) -> Int {
        guard laneCount > 1 else { return 0 }
        let current = nearestLane(for: vehicle.lateralPosition, laneCount: laneCount)
        guard vehicle.kind == .rival else { return current }
        let relativeDistance = vehicle.distance - playerDistance
        if (-35...145).contains(relativeDistance) {
            return nearestLane(for: playerLateral, laneCount: laneCount)
        }
        let weavePeriod = max(1, Int((playerDistance + Double(vehicle.id & 0xFF)) / 180))
        let offset = weavePeriod.isMultiple(of: 2) ? 1 : -1
        return (current + offset).clamped(to: 0...(laneCount - 1))
    }

    private func closestVehicleAhead(
        of vehicle: TrafficVehicleState,
        in vehicles: [TrafficVehicleState],
        laneCount: Int
    ) -> TrafficVehicleState? {
        let lane = nearestLane(for: vehicle.lateralPosition, laneCount: laneCount)
        return vehicles
            .filter {
                $0.id != vehicle.id
                    && nearestLane(for: $0.lateralPosition, laneCount: laneCount) == lane
                    && $0.distance > vehicle.distance
            }
            .min { $0.distance < $1.distance }
    }

    private func nearestLane(for lateral: Double, profile: TrackSectionProfile) -> Int {
        nearestLane(for: lateral, laneCount: profile.laneCount)
    }

    private func nearestLane(for lateral: Double, laneCount: Int) -> Int {
        guard laneCount > 1 else { return 0 }
        let raw = ((lateral.clamped(to: -1...1) + 1) * 0.5 * Double(laneCount)).rounded(.down)
        return Int(raw).clamped(to: 0...(laneCount - 1))
    }

    private func halfWidth(for kind: TrafficVehicleKind, roadHalfWidth: Double) -> Double {
        let meters: Double
        switch kind {
        case .commuter: meters = 0.96
        case .hauler: meters = 1.28
        case .rival: meters = 1.02
        }
        return (meters / max(roadHalfWidth, 1)).clamped(to: 0.08...0.34)
    }

    private func obstacleHalfWidth(for kind: TrackObstacleKind, roadHalfWidth: Double) -> Double {
        let meters: Double
        switch kind {
        case .neonBarrier: meters = 1.35
        case .pylon: meters = 0.72
        case .laserGate: meters = 1.08
        case .roadsideBillboardPost, .holoSignPylon, .neonPalmTrunk, .debris:
            return roadsideObstacleHalfWidth(for: kind)
        }
        return (meters / max(roadHalfWidth, 1)).clamped(to: 0.06...0.36)
    }

    private func roadsideObstacleHalfWidth(for kind: TrackObstacleKind) -> Double {
        switch kind {
        case .roadsideBillboardPost: 0.08
        case .neonPalmTrunk: 0.07
        case .holoSignPylon: 0.09
        case .debris: 0.11
        case .neonBarrier, .pylon, .laserGate: 0.08
        }
    }

    private mutating func randomUnit() -> Double {
        randomNumberGenerator.nextUnitDouble()
    }

    private func randomNumberGeneratorPreviewUnit(_ value: UInt64) -> Double {
        stableUnit(value ^ 0xD1B5_4A32_D192_ED03)
    }

    private func stableUnit(_ value: UInt64) -> Double {
        let mixed = mix(value)
        return Double(mixed >> 11) / Double(UInt64(1) << 53)
    }

    private func stableID(_ value: String) -> UInt64 {
        value.utf8.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }

    private func mix(_ value: UInt64) -> UInt64 {
        var result = value &+ 0x9E37_79B9_7F4A_7C15
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}

private struct RuntimeTrafficProfile: Equatable, Sendable {
    let baseDensity: Double
    let maximumVehicles: Int
    let minimumHeadwaySeconds: Double
    let speedRange: ClosedRange<Double>

    var minimumHeadwayMeters: Double {
        max(48, minimumHeadwaySeconds * max(speedRange.upperBound, 32))
    }

    func effectiveDensity(
        simulationDensity: Double,
        configuration: RaceConfiguration,
        progress: Double
    ) -> Double {
        let escalation = max(0, simulationDensity - configuration.traffic.baseDensity)
        return (baseDensity + escalation + progress * 0.05).clamped(to: 0...0.92)
    }
}

private func approach(_ value: Double, _ target: Double, maxDelta: Double) -> Double {
    if value < target { return min(value + maxDelta, target) }
    if value > target { return max(value - maxDelta, target) }
    return value
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
