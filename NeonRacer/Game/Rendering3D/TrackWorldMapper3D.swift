import Foundation
import SceneKit

struct TrackWorldFrame3D {
    let runDistance: Double
    let stageID: String
    let distanceInStage: Double
    let position: SCNVector3
    let heading: Float
    let pitch: Float
    let roadHalfWidth: Float
    let shoulderWidth: Float
    let laneCount: Int
    let laneWidth: Float

    var transform: SCNMatrix4 {
        var transform = SCNMatrix4Identity
        transform = SCNMatrix4Rotate(transform, pitch, 1, 0, 0)
        transform = SCNMatrix4Rotate(transform, yaw, 0, 1, 0)
        transform.m41 = position.x
        transform.m42 = position.y
        transform.m43 = position.z
        return transform
    }

    /// SceneKit Y rotation that points a node's -Z at `forward` (heading is clockwise from above; SceneKit yaw is counter-clockwise).
    var yaw: Float { -heading }

    var forward: SCNVector3 {
        SCNVector3(sin(heading), 0, -cos(heading))
    }

    var right: SCNVector3 {
        SCNVector3(cos(heading), 0, sin(heading))
    }
}

struct TrackStagePlacement3D {
    let stage: RouteStage
    let startRunDistance: Double
    let endRunDistance: Double
}

@MainActor
final class TrackWorldMapper3D {
    private struct CenterSample {
        let runDistance: Double
        let stageID: String
        let distanceInStage: Double
        let worldPosition: SCNVector3
        let heading: Float
        let pitch: Float
        let roadHalfWidth: Float
        let shoulderWidth: Float
        let laneCount: Int
        let laneWidth: Float
    }

    let layout: TrackLayout
    private(set) var placements: [TrackStagePlacement3D] = []
    private var centerSamples: [CenterSample] = []
    private var branchKey = ""
    private(set) var originWorldPosition = SCNVector3Zero
    private(set) var originVersion = 0
    private(set) var routeVersion = 0
    private let sampleSpacing: Double = 5

    init(layout: TrackLayout) {
        self.layout = layout
    }

    func updateRoute(for state: RaceState, presentationDistance: Double? = nil) {
        let key = state.committedBranchIDs.joined(separator: "|")
        if key != branchKey || placements.isEmpty {
            branchKey = key
            rebuildRoute(committedBranchIDs: state.committedBranchIDs)
            routeVersion += 1
        }
        rebase(around: presentationDistance ?? state.distance)
    }

    func frame(atRunDistance runDistance: Double, lateralPosition: Double = 0) -> TrackWorldFrame3D {
        guard !centerSamples.isEmpty else {
            return TrackWorldFrame3D(
                runDistance: runDistance,
                stageID: layout.routeGraph.startStageID,
                distanceInStage: 0,
                position: SCNVector3Zero,
                heading: 0,
                pitch: 0,
                roadHalfWidth: 6,
                shoulderWidth: 1,
                laneCount: 3,
                laneWidth: 4
            )
        }

        // Extend the launch road behind the car instead of collapsing negative
        // distances onto the first sample (which produces degenerate road chunks).
        if let first = centerSamples.first, runDistance < first.runDistance {
            let forward = SCNVector3(sin(first.heading), 0, -cos(first.heading))
            let right = SCNVector3(cos(first.heading), 0, sin(first.heading))
            let worldCenter = first.worldPosition + forward * Float(runDistance - first.runDistance)
            return TrackWorldFrame3D(
                runDistance: runDistance,
                stageID: first.stageID,
                distanceInStage: runDistance,
                position: worldCenter - originWorldPosition + right * (Float(lateralPosition) * first.roadHalfWidth),
                heading: first.heading,
                pitch: 0,
                roadHalfWidth: first.roadHalfWidth,
                shoulderWidth: first.shoulderWidth,
                laneCount: first.laneCount,
                laneWidth: first.laneWidth
            )
        }

        // Past the last authored sample (e.g. the finish-line cruise), extrapolate a straight,
        // level extension of the final heading so the road keeps going to the horizon.
        if let last = centerSamples.last, runDistance > last.runDistance {
            let extraDistance = runDistance - last.runDistance
            let forward = SCNVector3(sin(last.heading), 0, -cos(last.heading))
            let worldCenter = last.worldPosition + forward * Float(extraDistance)
            let right = SCNVector3(cos(last.heading), 0, sin(last.heading))
            let scenePosition = worldCenter - originWorldPosition
                + right * (Float(lateralPosition) * last.roadHalfWidth)
            return TrackWorldFrame3D(
                runDistance: runDistance,
                stageID: last.stageID,
                distanceInStage: last.distanceInStage + extraDistance,
                position: scenePosition,
                heading: last.heading,
                pitch: 0,
                roadHalfWidth: last.roadHalfWidth,
                shoulderWidth: last.shoulderWidth,
                laneCount: last.laneCount,
                laneWidth: last.laneWidth
            )
        }

        let distance = runDistance.clamped(to: centerSamples[0].runDistance...centerSamples.last!.runDistance)
        let upperIndex = centerSamples.partitioningIndex { $0.runDistance >= distance }
        let lowerIndex = max(0, min(centerSamples.count - 1, upperIndex - 1))
        let highIndex = min(centerSamples.count - 1, max(upperIndex, lowerIndex))
        let lower = centerSamples[lowerIndex]
        let upper = centerSamples[highIndex]
        let span = max(upper.runDistance - lower.runDistance, 0.0001)
        let t = Float((distance - lower.runDistance) / span)
        let worldCenter = lower.worldPosition.lerp(to: upper.worldPosition, t: t)
        let heading = lerpAngle(lower.heading, upper.heading, t)
        let pitch = lower.pitch + (upper.pitch - lower.pitch) * t
        let roadHalfWidth = lower.roadHalfWidth + (upper.roadHalfWidth - lower.roadHalfWidth) * t
        let lateralMeters = Float(lateralPosition) * roadHalfWidth
        let right = SCNVector3(cos(heading), 0, sin(heading))
        let sceneCenter = worldCenter - originWorldPosition
        let scenePosition = sceneCenter + right * lateralMeters

        return TrackWorldFrame3D(
            runDistance: distance,
            stageID: lower.stageID,
            distanceInStage: lower.distanceInStage + (upper.distanceInStage - lower.distanceInStage) * Double(t),
            position: scenePosition,
            heading: heading,
            pitch: pitch,
            roadHalfWidth: roadHalfWidth,
            shoulderWidth: lower.shoulderWidth + (upper.shoulderWidth - lower.shoulderWidth) * t,
            laneCount: lower.laneCount,
            laneWidth: lower.laneWidth + (upper.laneWidth - lower.laneWidth) * t
        )
    }

    /// Car/camera/actors use the chosen road's own tangent and elevation.
    /// Mesh and terrain callers continue to use the common route frame.
    func actorFrame(atRunDistance distance: Double, lateralPosition: Double, splitSide: Int? = nil) -> TrackWorldFrame3D {
        let base = frame(atRunDistance: distance)
        guard let cross = layout.splitCrossSection(stageID: base.stageID, distanceInStage: base.distanceInStage) else {
            return frame(atRunDistance: distance, lateralPosition: lateralPosition)
        }
        let meters = lateralPosition * cross.roadHalfWidth
        let side = splitSide ?? (abs(meters - cross.leftCenter) < abs(meters - cross.rightCenter) ? -1 : 1)
        let center = side < 0 ? cross.leftCenter : cross.rightCenter
        let halfWidth = side < 0 ? cross.leftHalfWidth : cross.rightHalfWidth
        return branchFrame(atRunDistance: distance, side: side, lateralPosition: (meters - center) / halfWidth)
    }

    func branchFrame(atRunDistance distance: Double, side: Int, lateralPosition: Double = 0) -> TrackWorldFrame3D {
        let base = frame(atRunDistance: distance)
        guard let path = layout.splitPath(stageID: base.stageID, distanceInStage: base.distanceInStage, side: side) else { return base }
        let heading = base.heading + Float(path.headingOffset)
        let branchRight = SCNVector3(cos(heading), 0, sin(heading))
        let position = base.position + base.right * Float(path.center)
            + SCNVector3(0, Float(path.elevationOffset), 0)
            + branchRight * Float(lateralPosition * path.halfWidth)
        return TrackWorldFrame3D(runDistance: distance, stageID: base.stageID, distanceInStage: base.distanceInStage,
                                 position: position, heading: heading,
                                 pitch: Float(atan(layout.sample(stageID: base.stageID, distanceInStage: base.distanceInStage).grade + path.gradeOffset)),
                                 roadHalfWidth: Float(path.halfWidth), shoulderWidth: base.shoulderWidth,
                                 laneCount: side < 0 ? 3 : layout.split(for: base.stageID)!.narrowLaneCount,
                                 laneWidth: base.laneWidth)
    }

    func runDistance(stageID: String, distanceInStage: Double) -> Double? {
        placements.first { $0.stage.id == stageID }.map { placement in
            placement.startRunDistance + distanceInStage.clamped(to: 0...placement.stage.distance)
        }
    }

    private func rebuildRoute(committedBranchIDs: [String]) {
        placements.removeAll(keepingCapacity: true)
        var stageID = layout.routeGraph.startStageID
        var start = 0.0
        var visited: Set<String> = []
        let committed = Set(committedBranchIDs)

        while let stage = layout.routeGraph.stage(id: stageID), !visited.contains(stageID) {
            visited.insert(stageID)
            let end = start + stage.distance
            placements.append(TrackStagePlacement3D(stage: stage, startRunDistance: start, endRunDistance: end))
            guard !stage.branches.isEmpty else { break }
            let selected = stage.branches.first { committed.contains($0.id) } ?? stage.branches[0]
            stageID = selected.destinationStageID
            start = end
        }
        rebuildCenterSamples()
    }

    private func rebuildCenterSamples() {
        centerSamples.removeAll(keepingCapacity: true)
        var worldPosition = SCNVector3Zero
        var heading: Float = 0
        var previousRunDistance = 0.0

        for placement in placements {
            var distance = 0.0
            // Stage elevations are authored per stage; offset each stage so the road stays continuous.
            let stageStartElevation = Float(layout.sample(stageID: placement.stage.id, distanceInStage: 0).elevation)
            let elevationOffset = centerSamples.isEmpty ? 0 : worldPosition.y - stageStartElevation
            while distance <= placement.stage.distance + 0.001 {
                let runDistance = placement.startRunDistance + distance
                let sample = layout.sample(stageID: placement.stage.id, distanceInStage: distance)
                if centerSamples.isEmpty {
                    worldPosition.y = Float(sample.elevation) + elevationOffset
                } else {
                    let delta = runDistance - previousRunDistance
                    let midDistance = max(0, distance - delta * 0.5)
                    let curvature = layout.sample(stageID: placement.stage.id, distanceInStage: midDistance).curvature
                    heading += Float(curvature * TrackSectionProfile.radiansPerMeterAtFullCurve * delta)
                    worldPosition.x += sin(heading) * Float(delta)
                    worldPosition.z -= cos(heading) * Float(delta)
                    worldPosition.y = Float(sample.elevation) + elevationOffset
                }
                let pitch = Float(atan(sample.grade))
                centerSamples.append(CenterSample(
                    runDistance: runDistance,
                    stageID: placement.stage.id,
                    distanceInStage: distance,
                    worldPosition: worldPosition,
                    heading: heading,
                    pitch: pitch,
                    roadHalfWidth: Float(sample.roadHalfWidth),
                    shoulderWidth: Float(sample.shoulderWidth),
                    laneCount: sample.laneCount,
                    laneWidth: Float(sample.laneWidth)
                ))
                previousRunDistance = runDistance
                distance += sampleSpacing
            }
        }
    }

    private func rebase(around runDistance: Double) {
        let currentWorld = worldCenter(atRunDistance: runDistance)
        let delta = currentWorld - originWorldPosition
        if delta.length > 80 || originVersion == 0 {
            originWorldPosition = currentWorld
            originVersion += 1
        }
    }

    private func worldCenter(atRunDistance runDistance: Double) -> SCNVector3 {
        guard !centerSamples.isEmpty else { return SCNVector3Zero }
        if let last = centerSamples.last, runDistance > last.runDistance {
            let forward = SCNVector3(sin(last.heading), 0, -cos(last.heading))
            return last.worldPosition + forward * Float(runDistance - last.runDistance)
        }
        let distance = runDistance.clamped(to: centerSamples[0].runDistance...centerSamples.last!.runDistance)
        let upperIndex = centerSamples.partitioningIndex { $0.runDistance >= distance }
        let lowerIndex = max(0, min(centerSamples.count - 1, upperIndex - 1))
        let highIndex = min(centerSamples.count - 1, max(upperIndex, lowerIndex))
        let lower = centerSamples[lowerIndex]
        let upper = centerSamples[highIndex]
        let span = max(upper.runDistance - lower.runDistance, 0.0001)
        return lower.worldPosition.lerp(to: upper.worldPosition, t: Float((distance - lower.runDistance) / span))
    }
}

private func lerpAngle(_ a: Float, _ b: Float, _ t: Float) -> Float {
    var delta = b - a
    while delta > .pi { delta -= 2 * .pi }
    while delta < -.pi { delta += 2 * .pi }
    return a + delta * t
}

extension Array {
    fileprivate func partitioningIndex(where belongsInSecondPartition: (Element) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if belongsInSecondPartition(self[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}

extension Comparable {
    fileprivate func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension SCNVector3 {
    static func + (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    static func - (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static func * (lhs: SCNVector3, rhs: Float) -> SCNVector3 {
        SCNVector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    var length: Float {
        sqrt(x * x + y * y + z * z)
    }

    func lerp(to other: SCNVector3, t: Float) -> SCNVector3 {
        self + (other - self) * t
    }
}

extension SCNVector3: @retroactive Equatable {
    public static func == (lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
}

extension SCNNode {
    func getBoundingBoxMin(_ minimum: UnsafeMutablePointer<SCNVector3>, max maximum: UnsafeMutablePointer<SCNVector3>) {
        let box = boundingBox
        minimum.pointee = box.min
        maximum.pointee = box.max
    }
}
