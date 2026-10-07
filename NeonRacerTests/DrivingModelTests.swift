import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct DrivingModelTests {
    @Test(arguments: [-1.0, 1.0])
    func bothSplitPathsCanBeDrivenAndMergeWithoutTeleporting(side: Double) {
        let layout = TrackLayout.initialContent()
        let configuration = RaceConfiguration.standard
        var vehicle = VehicleState()
        vehicle.speed = 80
        var runtime = DrivingModel.RuntimeState()
        var distance = 100.0
        var sawSeparatedRoad = false
        var offRoadFrames = 0
        for _ in 0..<3_000 where distance < 1_000 {
            let sample = layout.sample(stageID: "coast-solar-sweep", distanceInStage: distance)
            let cross = layout.splitCrossSection(stageID: "coast-solar-sweep", distanceInStage: distance + 30)
            let target = cross.map { (side < 0 ? $0.leftCenter : $0.rightCenter) / $0.roadHalfWidth } ?? 0
            let speedRatio = min(vehicle.speed / configuration.maximumSpeed, 1)
            let authority = configuration.driving.steeringAtRestRatio
                + (1 - configuration.driving.steeringAtRestRatio) * speedRatio
            let counterSteer = sample.curvature * vehicle.speed * vehicle.speed
                * configuration.driving.centrifugalForce / max(0.1, configuration.steeringRate * authority)
            let steering = min(max(counterSteer + (target - vehicle.roadPosition.lateralOffset) * 3, -1), 1)
            let before = vehicle.roadPosition.lateralOffset
            let update = DrivingModel.update(
                vehicle: vehicle,
                command: PlayerCommand(steering: steering, throttle: 1, brake: 0, isBoosting: false),
                trackSample: sample, configuration: configuration, isBoostActive: false,
                deltaTime: 1.0 / 120, runtime: &runtime
            )
            vehicle = update.vehicle
            distance += update.distanceDelta
            #expect(abs(vehicle.roadPosition.lateralOffset - before) < 0.04)
            if (400...700).contains(distance) {
                sawSeparatedRoad = true
                #expect(vehicle.roadPosition.lateralOffset * side > 0.1)
                if vehicle.isOffRoad { offRoadFrames += 1 }
            }
        }
        #expect(sawSeparatedRoad)
        #expect(offRoadFrames == 0)
        #expect(distance >= 1_000)
        #expect(abs(vehicle.roadPosition.lateralOffset) < 0.1)
    }

    @Test
    func centrifugalPushUsesCurveDirectionAndScalesWithMagnitude() {
        var runtime = DrivingModel.RuntimeState()
        let straight = updatedVehicle(curvature: 0, speed: 100, runtime: &runtime)
        runtime = DrivingModel.RuntimeState()
        let rightCurve = updatedVehicle(curvature: 0.4, speed: 100, runtime: &runtime)
        runtime = DrivingModel.RuntimeState()
        let tightRightCurve = updatedVehicle(curvature: 0.76, speed: 100, runtime: &runtime)
        runtime = DrivingModel.RuntimeState()
        let leftCurve = updatedVehicle(curvature: -0.4, speed: 100, runtime: &runtime)

        #expect(rightCurve.roadPosition.lateralOffset < straight.roadPosition.lateralOffset)
        #expect(leftCurve.roadPosition.lateralOffset > straight.roadPosition.lateralOffset)
        #expect(abs(tightRightCurve.roadPosition.lateralOffset)
            > abs(rightCurve.roadPosition.lateralOffset))
    }

    @Test
    func fullSteerCanHoldTightestContentCurveAtMaximumSpeed() {
        var runtime = DrivingModel.RuntimeState()
        var vehicle = VehicleState()
        vehicle.speed = RaceConfiguration.standard.maximumSpeed

        let update = DrivingModel.update(
            vehicle: vehicle,
            command: PlayerCommand(steering: 1, throttle: 1, brake: 0, isBoosting: false),
            trackSample: sample(curvature: 0.76),
            configuration: .standard,
            isBoostActive: false,
            deltaTime: 1.0 / 120.0,
            runtime: &runtime
        )

        #expect(update.vehicle.roadPosition.lateralOffset >= 0)
        #expect(update.vehicle.isOffRoad == false)
    }

    @Test
    func offRoadAppliesStrongSpeedCapAndSurfaceFlag() {
        var runtime = DrivingModel.RuntimeState()
        var vehicle = VehicleState()
        vehicle.speed = RaceConfiguration.standard.maximumSpeed
        vehicle.roadPosition.lateralOffset = 1.35

        for _ in 0..<120 {
            let update = DrivingModel.update(
                vehicle: vehicle,
                command: PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false),
                trackSample: sample(curvature: 0),
                configuration: .standard,
                isBoostActive: false,
                deltaTime: 1.0 / 120.0,
                runtime: &runtime
            )
            vehicle = update.vehicle
        }

        #expect(vehicle.isOffRoad)
        #expect(vehicle.speed <= RaceConfiguration.standard.maximumSpeed
            * RaceConfiguration.standard.driving.offRoadSpeedLimitRatio + 0.5)
    }

    @Test
    func softWallClampsLateralRangeAndBleedsSpeed() {
        var runtime = DrivingModel.RuntimeState()
        var vehicle = VehicleState()
        vehicle.speed = 100
        vehicle.roadPosition.lateralOffset = 1.44

        let update = DrivingModel.update(
            vehicle: vehicle,
            command: PlayerCommand(steering: 1, throttle: 1, brake: 0, isBoosting: false),
            trackSample: sample(curvature: -0.76),
            configuration: .standard,
            isBoostActive: false,
            deltaTime: 1.0 / 30.0,
            runtime: &runtime
        )

        #expect(update.vehicle.roadPosition.lateralOffset
            <= RaceConfiguration.standard.driving.lateralLimit)
        #expect(update.vehicle.speed < 100)
    }

    @Test
    func driftEntersExitsAndScoresOncePerSlide() {
        var simulation = RaceSimulation(
            seed: 44,
            routeGraph: InitialRouteContent.routeGraph(),
            countdownDuration: 0
        )
        let throttle = PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false)
        advance(&simulation, seconds: 3.2, command: throttle)

        let drift = PlayerCommand(steering: 1, throttle: 1, brake: 0.25, isBoosting: false)
        advance(&simulation, seconds: 0.75, command: drift)
        #expect(simulation.state.vehicle.isDrifting)

        advance(&simulation, seconds: 0.8, command: throttle)

        #expect(simulation.state.vehicle.isDrifting == false)
        #expect(simulation.scoreEvents.filter { $0.source == .drift }.count == 1)
        #expect(simulation.state.scoreInputs.driftPoints > 0)
    }

    @Test
    func crashRecoveryReducesSteeringAndTicksDown() {
        var normalRuntime = DrivingModel.RuntimeState()
        var recoveringRuntime = DrivingModel.RuntimeState()
        var normal = VehicleState()
        normal.speed = 90
        var recovering = normal
        recovering.crashRecoveryRemaining = 1

        let normalUpdate = DrivingModel.update(
            vehicle: normal,
            command: PlayerCommand(steering: 1, throttle: 1, brake: 0, isBoosting: false),
            trackSample: sample(curvature: 0),
            configuration: .standard,
            isBoostActive: false,
            deltaTime: 1.0 / 30.0,
            runtime: &normalRuntime
        )
        let recoveringUpdate = DrivingModel.update(
            vehicle: recovering,
            command: PlayerCommand(steering: 1, throttle: 1, brake: 0, isBoosting: false),
            trackSample: sample(curvature: 0),
            configuration: .standard,
            isBoostActive: false,
            deltaTime: 1.0 / 30.0,
            runtime: &recoveringRuntime
        )

        #expect(recoveringUpdate.vehicle.roadPosition.lateralOffset
            < normalUpdate.vehicle.roadPosition.lateralOffset)
        #expect(recoveringUpdate.vehicle.crashRecoveryRemaining < 1)
    }

    @Test
    func drivingModelIsDeterministicThroughRaceSimulation() {
        let commands = [
            PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false),
            PlayerCommand(steering: 0.8, throttle: 1, brake: 0.2, isBoosting: false),
            PlayerCommand(steering: -0.7, throttle: 0.8, brake: 0, isBoosting: true),
            PlayerCommand(steering: 0, throttle: 1, brake: 0, isBoosting: false)
        ]
        var first = RaceSimulation(seed: 99, routeGraph: InitialRouteContent.routeGraph())
        var second = RaceSimulation(seed: 99, routeGraph: InitialRouteContent.routeGraph())

        for frame in 0..<1_200 {
            let command = commands[min(commands.count - 1, frame / 300)]
            first.advance(frameDelta: 1.0 / 60.0, command: command)
            second.advance(frameDelta: 1.0 / 60.0, command: command)
        }

        #expect(first.state == second.state)
        #expect(first.scoreEvents == second.scoreEvents)
    }

    private func updatedVehicle(
        curvature: Double,
        speed: Double,
        runtime: inout DrivingModel.RuntimeState
    ) -> VehicleState {
        var vehicle = VehicleState()
        vehicle.speed = speed
        return DrivingModel.update(
            vehicle: vehicle,
            command: PlayerCommand(steering: 0, throttle: 0, brake: 0, isBoosting: false),
            trackSample: sample(curvature: curvature),
            configuration: .standard,
            isBoostActive: false,
            deltaTime: 1.0 / 120.0,
            runtime: &runtime
        ).vehicle
    }

    private func advance(
        _ simulation: inout RaceSimulation,
        seconds: TimeInterval,
        command: PlayerCommand
    ) {
        for _ in 0..<Int(seconds * 120) {
            simulation.advance(frameDelta: 1.0 / 120.0, command: command)
        }
    }

    private func sample(curvature: Double, grade: Double = 0) -> TrackSample {
        TrackSample(
            stageID: "test",
            distanceInStage: 0,
            curvature: curvature,
            elevation: 0,
            grade: grade,
            laneCount: 3,
            laneWidth: 4,
            roadHalfWidth: 6,
            shoulderWidth: 1.2,
            isStartZone: false,
            isFinishZone: false
        )
    }
}
