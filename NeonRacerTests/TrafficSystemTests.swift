import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct TrafficSystemTests {
    @Test
    func spawningIsDeterministicForSameSeed() throws {
        let first = try sampledTraffic(seed: 0xCAFE)
        let second = try sampledTraffic(seed: 0xCAFE)

        #expect(first.traffic == second.traffic)
        #expect(first.obstacles == second.obstacles)
        #expect(!first.traffic.isEmpty)
    }

    @Test
    func spawningLeavesEscapeLaneAndAvoidsStartAndFinishZones() throws {
        let route = InitialRouteContent.routeGraph()
        let layout = TrackLayout.initialContent()
        var system = TrafficSystem(seed: 99)
        let stage = try #require(route.stage(id: "coast-causeway"))
        var state = RaceState(
            elapsedTime: 8,
            vehicle: VehicleState(),
            timerRemaining: 90,
            boostCharge: 0,
            stageProgress: 0.25,
            trafficDensity: 0.86,
            phase: .racing,
            countdownRemaining: 0,
            currentStageID: stage.id,
            currentStageDistance: 120,
            currentEnvironmentID: stage.environmentID
        )
        state.distance = 120
        state.speed = 92
        var sawOnRoadObstacle = false
        var sawRoadsideObstacle = false

        for _ in 0..<260 {
            system.update(
                state: &state,
                configuration: .standard,
                trackLayout: layout,
                currentStage: stage,
                stageStartDistance: 0,
                deltaTime: 1.0 / 30.0
            )
            state.distance += 5
            state.currentStageDistance = state.distance
            state.stageProgress = min(state.currentStageDistance / stage.distance, 1)
            sawOnRoadObstacle = sawOnRoadObstacle || state.obstacles.contains { abs($0.lateralPosition) <= 1 }
            sawRoadsideObstacle = sawRoadsideObstacle
                || state.obstacles.contains { (1.1...1.45).contains(abs($0.lateralPosition)) }
        }

        #expect(state.traffic.allSatisfy { $0.distance >= TrackLayout.startGridLength })
        #expect(state.obstacles.allSatisfy { $0.distance >= TrackLayout.startGridLength })
        #expect(sawOnRoadObstacle)
        #expect(sawRoadsideObstacle)
        assertEscapeLaneRemainsOpen(state: state, layout: layout, stageID: stage.id)

        let finalStage = try #require(route.stage(id: "peaks-summit-finish"))
        var finalSystem = TrafficSystem(seed: 100)
        var finalState = state
        finalState.traffic.removeAll()
        finalState.obstacles.removeAll()
        finalState.currentStageID = finalStage.id
        finalState.currentEnvironmentID = finalStage.environmentID
        finalState.currentStageDistance = 120
        finalState.stageProgress = 0.2
        let stageStart = 7_000.0
        finalState.distance = stageStart + 120
        for _ in 0..<220 {
            finalSystem.update(
                state: &finalState,
                configuration: .standard,
                trackLayout: layout,
                currentStage: finalStage,
                stageStartDistance: stageStart,
                deltaTime: 1.0 / 30.0
            )
            finalState.distance += 5
            finalState.currentStageDistance = finalState.distance - stageStart
            finalState.stageProgress = min(finalState.currentStageDistance / finalStage.distance, 1)
        }
        let finishBufferStart = stageStart + finalStage.distance - 150
        #expect(finalState.traffic.allSatisfy { $0.distance < finishBufferStart })
        #expect(finalState.obstacles.allSatisfy { $0.distance < finishBufferStart })
    }

    @Test
    func despawnsVehiclesAndObstaclesBehindPlayer() throws {
        let route = InitialRouteContent.routeGraph()
        let layout = TrackLayout.initialContent()
        let stage = try #require(route.stage(id: "coast-causeway"))
        var system = TrafficSystem(seed: 1)
        var state = RaceState(
            timerRemaining: 90,
            trafficDensity: 0.5,
            phase: .racing,
            currentStageID: stage.id,
            currentStageDistance: 500,
            currentEnvironmentID: stage.environmentID
        )
        state.distance = 500
        state.traffic = [TrafficVehicleState(
            id: 1,
            kind: .commuter,
            distance: 390,
            lateralPosition: 0,
            speed: 60,
            halfWidth: 0.1
        )]
        state.obstacles = [TrackObstacleState(
            id: 2,
            kind: .pylon,
            distance: 390,
            lateralPosition: 0,
            halfWidth: 0.08
        )]

        system.update(
            state: &state,
            configuration: .standard,
            trackLayout: layout,
            currentStage: stage,
            stageStartDistance: 0,
            deltaTime: 1.0 / 60.0
        )

        #expect(state.traffic.allSatisfy { $0.distance >= 420 })
        #expect(state.obstacles.allSatisfy { $0.distance >= 420 })
    }

    @Test
    func simulationTrafficReplayIsDeterministic() {
        var first = RaceSimulation(seed: 0x1234, routeGraph: InitialRouteContent.routeGraph(), countdownDuration: 0)
        var second = RaceSimulation(seed: 0x1234, routeGraph: InitialRouteContent.routeGraph(), countdownDuration: 0)
        let command = PlayerCommand(steering: 0.35, throttle: 1, brake: 0, isBoosting: false)

        for _ in 0..<1_800 {
            first.advance(frameDelta: 1.0 / 120.0, command: command)
            second.advance(frameDelta: 1.0 / 120.0, command: command)
        }

        #expect(first.state == second.state)
        #expect(first.scoreEvents == second.scoreEvents)
        #expect(first.feedbackEvents == second.feedbackEvents)
    }

    @Test
    func spawnsSkipBlindCrestSightlineWindow() throws {
        let stage = RouteStage(
            id: "crest-stage",
            displayName: "Crest Stage",
            environmentID: "test",
            distance: 1_200,
            checkpointTimeAward: 0,
            branches: []
        )
        let route = RouteGraph(
            startStageID: stage.id,
            stages: [stage],
            forkDecisionDistance: 0,
            minimumForkDecisionTime: 0
        )
        let section = RoadSectionDefinition(
            id: stage.id,
            length: stage.distance,
            curve: CurveDefinition(entry: 0, apex: 0, exit: 0),
            elevation: ElevationDefinition(startMeters: 0, endMeters: -12, crestMeters: 90),
            lanes: LaneDefinition(count: 3, width: 4, shoulderWidth: 1.2),
            laneChanges: [],
            links: []
        )
        let layout = TrackLayout(routeGraph: route, sections: [section])
        var system = TrafficSystem(seed: 41)
        var state = RaceState(
            elapsedTime: 12,
            vehicle: VehicleState(),
            timerRemaining: 90,
            boostCharge: 0,
            stageProgress: 0.25,
            trafficDensity: 0.9,
            phase: .racing,
            countdownRemaining: 0,
            currentStageID: stage.id,
            currentStageDistance: 260,
            currentEnvironmentID: stage.environmentID
        )
        state.distance = 260
        state.speed = 90
        var trafficSpawnDistances: [UInt64: Double] = [:]
        var obstacleSpawnDistances: [UInt64: Double] = [:]

        for _ in 0..<80 {
            system.update(
                state: &state,
                configuration: .standard,
                trackLayout: layout,
                currentStage: stage,
                stageStartDistance: 0,
                deltaTime: 1.0 / 30.0
            )
            for vehicle in state.traffic where trafficSpawnDistances[vehicle.id] == nil {
                trafficSpawnDistances[vehicle.id] = vehicle.distance
            }
            for obstacle in state.obstacles where obstacleSpawnDistances[obstacle.id] == nil {
                obstacleSpawnDistances[obstacle.id] = obstacle.distance
            }
        }

        let blindWindow = 600.0...750.0
        #expect(!state.traffic.isEmpty || !state.obstacles.isEmpty)
        #expect(trafficSpawnDistances.values.allSatisfy { !blindWindow.contains($0) })
        #expect(obstacleSpawnDistances.values.allSatisfy { !blindWindow.contains($0) })
    }

    private func sampledTraffic(seed: UInt64) throws -> RaceState {
        let route = InitialRouteContent.routeGraph()
        let layout = TrackLayout.initialContent()
        let stage = try #require(route.stage(id: "coast-causeway"))
        var system = TrafficSystem(seed: seed)
        var state = RaceState(
            elapsedTime: 10,
            vehicle: VehicleState(),
            timerRemaining: 90,
            boostCharge: 0,
            stageProgress: 0.2,
            trafficDensity: 0.78,
            phase: .racing,
            countdownRemaining: 0,
            currentStageID: stage.id,
            currentStageDistance: 100,
            currentEnvironmentID: stage.environmentID
        )
        state.distance = 100
        state.speed = 90
        for _ in 0..<160 {
            system.update(
                state: &state,
                configuration: .standard,
                trackLayout: layout,
                currentStage: stage,
                stageStartDistance: 0,
                deltaTime: 1.0 / 30.0
            )
            state.distance += 4
            state.currentStageDistance = state.distance
            state.stageProgress = min(state.currentStageDistance / stage.distance, 1)
        }
        return state
    }

    private func assertEscapeLaneRemainsOpen(state: RaceState, layout: TrackLayout, stageID: String) {
        let profile = layout.profile(for: stageID)
        let distances = state.traffic.map(\.distance) + state.obstacles.map(\.distance)
        for distance in distances {
            var lanes = Set<Int>()
            for vehicle in state.traffic where abs(vehicle.distance - distance) <= 58 {
                lanes.insert(nearestLane(vehicle.lateralPosition, laneCount: profile.laneCount))
            }
            for obstacle in state.obstacles
            where !obstacle.isHit
                && abs(obstacle.lateralPosition) <= 1
                && abs(obstacle.distance - distance) <= 58 {
                lanes.insert(nearestLane(obstacle.lateralPosition, laneCount: profile.laneCount))
            }
            #expect(lanes.count < profile.laneCount)
        }
    }

    private func nearestLane(_ lateral: Double, laneCount: Int) -> Int {
        let raw = ((min(max(lateral, -1), 1) + 1) * 0.5 * Double(laneCount)).rounded(.down)
        return min(max(Int(raw), 0), laneCount - 1)
    }
}
