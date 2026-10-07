import Foundation

/// Deterministic road shape shared by the simulation and every renderer.
///
/// Coordinate conventions:
/// - Distances are meters along the committed route, matching `RaceState.distance`.
/// - `lateralPosition` values are normalized: -1 is the left road edge, +1 the right road edge.
/// - Positive curvature bends the road to the right.
struct TrackSectionProfile: Codable, Equatable, Sendable {
    var length: Double
    var curveEntry: Double
    var curveApex: Double
    var curveExit: Double
    var elevationStart: Double
    var elevationEnd: Double
    var elevationCrest: Double?
    var laneCount: Int
    var laneWidth: Double
    var shoulderWidth: Double

    /// Heading change in radians per meter for a normalized curvature of 1.
    static let radiansPerMeterAtFullCurve = 0.004

    var roadHalfWidth: Double { Double(laneCount) * laneWidth / 2 }

    /// Normalized curvature, blended smoothly entry -> apex -> exit.
    func curvature(at distance: Double) -> Double {
        let t = normalized(distance)
        if t < 0.5 {
            return lerp(curveEntry, curveApex, smoothstep(t / 0.5))
        }
        return lerp(curveApex, curveExit, smoothstep((t - 0.5) / 0.5))
    }

    /// Absolute elevation in meters. Passes through the crest at the section midpoint when present.
    func elevation(at distance: Double) -> Double {
        let t = normalized(distance)
        guard let crest = elevationCrest else {
            return lerp(elevationStart, elevationEnd, smoothstep(t))
        }
        let control = 2 * crest - 0.5 * (elevationStart + elevationEnd)
        let inverse = 1 - t
        return inverse * inverse * elevationStart + 2 * inverse * t * control + t * t * elevationEnd
    }

    /// Rise over run at `distance`.
    func grade(at distance: Double) -> Double {
        let step = 1.0
        let lower = max(0, distance - step)
        let upper = min(length, distance + step)
        guard upper > lower else { return 0 }
        return (elevation(at: upper) - elevation(at: lower)) / (upper - lower)
    }

    func laneCenter(_ lane: Int) -> Double {
        guard laneCount > 0 else { return 0 }
        let clamped = min(max(lane, 0), laneCount - 1)
        return (Double(clamped) + 0.5) / Double(laneCount) * 2 - 1
    }

    private func normalized(_ distance: Double) -> Double {
        guard length > 0 else { return 0 }
        return min(max(distance / length, 0), 1)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

struct TrackSample: Equatable, Sendable {
    let stageID: String
    let distanceInStage: Double
    let curvature: Double
    let elevation: Double
    let grade: Double
    let laneCount: Int
    let laneWidth: Double
    let roadHalfWidth: Double
    let shoulderWidth: Double
    let isStartZone: Bool
    let isFinishZone: Bool
}

enum TrackZoneKind: String, Codable, Equatable, Sendable {
    case startGrid
    case startLine
    case checkpoint
    case forkSplit
    case finishLine
}

/// A notable world marker along one stage, used for start/finish/checkpoint visuals.
struct TrackZoneMarker: Codable, Equatable, Sendable {
    let kind: TrackZoneKind
    let stageID: String
    let distanceInStage: Double
}

/// A physical tunnel embedded in a road section; distances remain in the same
/// stage coordinate system as the simulation, road mesh, and camera.
struct TrackTunnelSection: Equatable, Sendable {
    let entrance: Double
    let exit: Double
    let ceilingHeight: Double

    func contains(_ distance: Double) -> Bool { distance >= entrance && distance <= exit }

    /// Lower the chase camera before the portal and restore it only after the
    /// camera (which trails the car) has cleared the exit.
    func cameraBlend(at distance: Double) -> Double {
        func smooth(_ value: Double) -> Double {
            let t = min(max(value, 0), 1)
            return t * t * (3 - 2 * t)
        }
        return smooth((distance - entrance + 60) / 60)
            * (1 - smooth((distance - exit - 24) / 60))
    }
}

struct TrackLayout: Equatable, Sendable {
    /// The start grid occupies the first meters of the start stage; the start line gantry sits at its end.
    static let startGridLength = 40.0
    static let startLineDistance = 12.0
    /// Ease from the level launch straight into the authored road over 120 meters.
    static let startTransitionLength = 120.0
    /// The finish zone extends before the end of every stage with no branches.
    static let finishZoneLength = 60.0

    let routeGraph: RouteGraph
    private let profiles: [String: TrackSectionProfile]

    init(routeGraph: RouteGraph, sections: [RoadSectionDefinition] = []) {
        self.routeGraph = routeGraph
        let sectionsByID = Dictionary(
            sections.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var profiles: [String: TrackSectionProfile] = [:]
        for stage in routeGraph.stages {
            if let section = sectionsByID[stage.id] {
                profiles[stage.id] = TrackSectionProfile(
                    length: stage.distance,
                    curveEntry: section.curve.entry,
                    curveApex: section.curve.apex,
                    curveExit: section.curve.exit,
                    elevationStart: section.elevation.startMeters,
                    elevationEnd: section.elevation.endMeters,
                    elevationCrest: section.elevation.crestMeters,
                    laneCount: max(1, section.lanes.count),
                    laneWidth: section.lanes.width,
                    shoulderWidth: section.lanes.shoulderWidth
                )
            } else {
                profiles[stage.id] = Self.proceduralProfile(for: stage)
            }
        }
        self.profiles = profiles
    }

    /// Layout for the bundled content route, with authored curves and hills.
    static func initialContent() -> TrackLayout {
        TrackLayout(
            routeGraph: InitialRouteContent.routeGraph(),
            sections: InitialRouteContent.bundle.document.stage.route.sections
        )
    }

    /// Chooses authored sections when the graph's stages come from bundled content, otherwise procedural shapes.
    static func forRoute(_ routeGraph: RouteGraph) -> TrackLayout {
        TrackLayout(routeGraph: routeGraph, sections: InitialRouteContent.bundle.document.stage.route.sections)
    }

    func tunnel(for stageID: String) -> TrackTunnelSection? {
        guard stageID == "city-axis-tunnel" || stageID == "skyline-2",
              let stage = routeGraph.stage(id: stageID), stage.distance >= 240 else { return nil }
        return TrackTunnelSection(entrance: 120, exit: stage.distance - 120, ceilingHeight: 5.2)
    }

    func profile(for stageID: String) -> TrackSectionProfile {
        profiles[stageID] ?? Self.fallbackProfile
    }

    func isFinalStage(_ stageID: String) -> Bool {
        routeGraph.stage(id: stageID)?.branches.isEmpty ?? true
    }

    func sample(stageID: String, distanceInStage: Double) -> TrackSample {
        let profile = profile(for: stageID)
        let isStart = stageID == routeGraph.startStageID && distanceInStage < Self.startGridLength
        let isFinish = isFinalStage(stageID) && distanceInStage >= profile.length - Self.finishZoneLength
        let isOpeningStage = stageID == routeGraph.startStageID
        let transitionLength = min(Self.startTransitionLength, max(0, profile.length - Self.startGridLength))
        let blend: Double
        let blendDerivative: Double
        if isOpeningStage && distanceInStage < Self.startGridLength {
            blend = 0
            blendDerivative = 0
        } else if isOpeningStage && transitionLength > 0 {
            let t = min(max((distanceInStage - Self.startGridLength) / transitionLength, 0), 1)
            blend = t * t * (3 - 2 * t)
            blendDerivative = 6 * t * (1 - t) / transitionLength
        } else {
            blend = 1
            blendDerivative = 0
        }
        let elevationDelta = profile.elevation(at: distanceInStage) - profile.elevationStart
        return TrackSample(
            stageID: stageID,
            distanceInStage: distanceInStage,
            curvature: profile.curvature(at: distanceInStage) * blend,
            elevation: profile.elevationStart + elevationDelta * blend,
            grade: profile.grade(at: distanceInStage) * blend + elevationDelta * blendDerivative,
            laneCount: profile.laneCount,
            laneWidth: profile.laneWidth,
            roadHalfWidth: profile.roadHalfWidth,
            shoulderWidth: profile.shoulderWidth,
            isStartZone: isStart,
            isFinishZone: isFinish
        )
    }

    /// Start, checkpoint, fork, and finish markers for one stage.
    func markers(for stageID: String) -> [TrackZoneMarker] {
        guard let stage = routeGraph.stage(id: stageID) else { return [] }
        var markers: [TrackZoneMarker] = []
        if stageID == routeGraph.startStageID {
            markers.append(TrackZoneMarker(kind: .startGrid, stageID: stageID, distanceInStage: 0))
            markers.append(TrackZoneMarker(kind: .startLine, stageID: stageID, distanceInStage: Self.startLineDistance))
        }
        if stage.branches.isEmpty {
            markers.append(TrackZoneMarker(kind: .finishLine, stageID: stageID, distanceInStage: stage.distance))
        } else {
            if stage.checkpointTimeAward > 0 {
                markers.append(TrackZoneMarker(kind: .checkpoint, stageID: stageID, distanceInStage: stage.distance))
            }
            if stage.branches.count > 1 {
                markers.append(TrackZoneMarker(
                    kind: .forkSplit,
                    stageID: stageID,
                    distanceInStage: max(0, stage.distance - routeGraph.forkDecisionDistance)
                ))
            }
        }
        return markers
    }

    private static let fallbackProfile = TrackSectionProfile(
        length: 1_000,
        curveEntry: 0,
        curveApex: 0,
        curveExit: 0,
        elevationStart: 0,
        elevationEnd: 0,
        elevationCrest: nil,
        laneCount: 3,
        laneWidth: 4,
        shoulderWidth: 1.2
    )

    /// Deterministic, stage-ID-seeded shape so fixture graphs still have turns and hills.
    private static func proceduralProfile(for stage: RouteStage) -> TrackSectionProfile {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in stage.id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        func unit(_ shift: UInt64) -> Double {
            Double((hash >> shift) & 0xFFFF) / Double(0xFFFF) * 2 - 1
        }
        return TrackSectionProfile(
            length: stage.distance,
            curveEntry: unit(0) * 0.2,
            curveApex: unit(16) * 0.6,
            curveExit: unit(32) * 0.2,
            elevationStart: 0,
            elevationEnd: unit(48) * 12,
            elevationCrest: unit(8) * 24,
            laneCount: 3,
            laneWidth: 4,
            shoulderWidth: 1.2
        )
    }
}

// MARK: - Shared actor state rendered by the 3D scene

enum TrafficVehicleKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// Slow, predictable commuter car.
    case commuter
    /// Wide cargo hauler occupying most of a lane.
    case hauler
    /// Aggressive rival that changes lanes and races the player.
    case rival
}

struct TrafficVehicleState: Codable, Equatable, Sendable, Identifiable {
    var id: UInt64
    var kind: TrafficVehicleKind
    /// Run distance in meters, same space as `RaceState.distance`.
    var distance: Double
    /// Normalized lateral position, -1...1.
    var lateralPosition: Double
    var speed: Double
    /// Normalized visual width of the vehicle body.
    var halfWidth: Double
    /// -1...1 steering/lean hint for renderers.
    var steering: Double = 0
    var isBraking: Bool = false
    var hasBeenPassed: Bool = false
}

enum TrackObstacleKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// Glowing lane-closure barrier.
    case neonBarrier
    /// Small pylon cluster.
    case pylon
    /// Hovering holographic gate the player must avoid.
    case laserGate
    /// Off-road sign support that punishes shortcutting through the shoulder.
    case roadsideBillboardPost
    /// Off-road synth-palm trunk close to the road edge.
    case neonPalmTrunk
    /// Off-road hologram support pylon.
    case holoSignPylon
    /// Loose off-road debris cluster.
    case debris
}

struct TrackObstacleState: Codable, Equatable, Sendable, Identifiable {
    var id: UInt64
    var kind: TrackObstacleKind
    var distance: Double
    var lateralPosition: Double
    var halfWidth: Double
    var isHit: Bool = false
}
