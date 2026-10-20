import Foundation

struct RouteReference: Encodable {
    let graph: RouteGraph
    let profiles: [String: TrackSectionProfile]
}

struct DrivingReference: Encodable {
    let name: String
    let profile: String
    let command: PlayerCommand
    let curvature: Double
    let grade: Double
    let initialLateral: Double
    let initialSpeed: Double
    let boosting: Bool
    let steps: Int
    let speed: Double
    let lateral: Double
    let slip: Double
    let drifting: Bool
}

struct Reference: Encodable {
    let routes: [String: RouteReference]
    let driving: [DrivingReference]
    let trackSamples: [TrackReference]
}

struct TrackReference: Encodable {
    let stage: String
    let distance: Double
    let side: Int
    let curvature: Double
    let grade: Double
    let elevation: Double
    let halfWidth: Double
}

var routes: [String: RouteReference] = [:]
var driving: [DrivingReference] = []
for difficulty in DifficultyProfile.allCases {
    let configuration = RaceConfiguration.configuration(for: difficulty)
    for route in ProgressionCatalog.routes {
        let graph = ProgressionCatalog.routeGraph(id: route.id, configuration: configuration)
        let layout = TrackLayout.forRoute(graph)
        routes["\(route.id)/\(difficulty.rawValue)"] = RouteReference(
            graph: graph,
            profiles: Dictionary(uniqueKeysWithValues: graph.stages.map {
                ($0.id, layout.profile(for: $0.id))
            })
        )
    }
    for scenario in [
        ("accelerate", 0.0, 0.0, 0.0, 0.0, 0.0, false, 0.0),
        ("boost", 0.0, 0.0, 0.0, 0.0, 0.0, true, 0.0),
        ("curve", 0.25, 0.35, 0.04, 0.0, 80.0, false, 0.0),
        ("offroad", -0.1, 0.0, 0.0, 1.3, 110.0, false, 0.0),
        ("drift", 0.9, 0.4, 0.0, 0.0, 115.0, false, 0.2),
        ("brake", 0.0, 0.0, -0.06, 0.0, 100.0, false, 1.0)
    ] {
        let (name, steering, curvature, grade, lateral, speed, boosting, brake) = scenario
        let command = PlayerCommand(steering: steering, throttle: 1, brake: brake, isBoosting: boosting)
        let sample = TrackSample(
            stageID: "reference", distanceInStage: 0, curvature: curvature,
            elevation: 0, grade: grade, laneCount: 3, laneWidth: 4,
            roadHalfWidth: 6, shoulderWidth: 1.2, isStartZone: false, isFinishZone: false
        )
        var vehicle = VehicleState(roadPosition: RoadPosition(lateralOffset: lateral), speed: speed)
        var runtime = DrivingModel.RuntimeState()
        for _ in 0..<120 {
            vehicle = DrivingModel.update(
                vehicle: vehicle, command: command, trackSample: sample,
                configuration: configuration, isBoostActive: boosting,
                deltaTime: configuration.fixedTimeStep, runtime: &runtime
            ).vehicle
        }
        driving.append(DrivingReference(
            name: name, profile: difficulty.rawValue, command: command,
            curvature: curvature, grade: grade, initialLateral: lateral,
            initialSpeed: speed, boosting: boosting, steps: 120,
            speed: vehicle.speed, lateral: vehicle.roadPosition.lateralOffset,
            slip: vehicle.slipAngle, drifting: vehicle.isDrifting
        ))
    }
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let output = URL(fileURLWithPath: CommandLine.arguments[1])
var trackSamples: [TrackReference] = []
let layout = TrackLayout.initialContent()
for stage in InitialRouteContent.routeGraph().stages {
    for fraction in [0.0, 0.05, 0.21, 0.3, 0.5, 0.7, 0.81, 0.9, 1.0] {
        for side in [-1, 1] {
            let distance = stage.distance * fraction
            let sample = layout.drivingSample(
                stageID: stage.id, distanceInStage: distance, splitSide: side
            )
            trackSamples.append(TrackReference(
                stage: stage.id, distance: distance, side: side,
                curvature: sample.curvature, grade: sample.grade,
                elevation: sample.elevation, halfWidth: sample.roadHalfWidth
            ))
        }
    }
}
try encoder.encode(Reference(
    routes: routes, driving: driving, trackSamples: trackSamples
)).write(to: output, options: .atomic)
