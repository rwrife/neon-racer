import Foundation
import SceneKit

@MainActor
final class RoadMeshBuilder3D {
    let rootNode = SCNNode()
    private var chunks: [Int: SCNNode] = [:]
    private var chunkOrigins: [Int: SCNVector3] = [:]
    private var lastOriginVersion = -1
    private var lastRouteVersion = -1
    private let chunkLength = 48.0
    private let sampleSpacing = 6.0
    private let behindDistance = 120.0
    private let aheadDistance = 840.0
    private let asphaltMaterial = RoadMeshBuilder3D.material(
        diffuse: UIColor(red: 0.07, green: 0.02, blue: 0.10, alpha: 1),
        emission: UIColor(red: 0.10, green: 0.02, blue: 0.16, alpha: 1)
    )
    private let shoulderMaterial = RoadMeshBuilder3D.material(
        diffuse: UIColor(red: 0.03, green: 0.01, blue: 0.06, alpha: 1),
        emission: UIColor(red: 0.08, green: 0.00, blue: 0.12, alpha: 1)
    )
    private let magentaMaterial = RoadMeshBuilder3D.material(
        diffuse: .magenta,
        emission: UIColor(red: 1, green: 0.02, blue: 0.75, alpha: 1)
    )
    private let cyanMaterial = RoadMeshBuilder3D.material(
        diffuse: .cyan,
        emission: UIColor(red: 0.0, green: 0.95, blue: 1, alpha: 1)
    )
    private let amberMaterial = RoadMeshBuilder3D.material(
        diffuse: .orange,
        emission: UIColor(red: 1, green: 0.55, blue: 0.05, alpha: 1)
    )
    private let offRoadGridMaterial = RoadMeshBuilder3D.material(
        diffuse: UIColor(red: 0.35, green: 0.04, blue: 0.32, alpha: 1),
        emission: UIColor(red: 0.32, green: 0.02, blue: 0.42, alpha: 1)
    )

    /// Dim cyan lattice etched into the asphalt, like the reference's grid road.
    private let surfaceGridMaterial = RoadMeshBuilder3D.material(
        diffuse: UIColor(red: 0.0, green: 0.22, blue: 0.3, alpha: 1),
        emission: UIColor(red: 0.0, green: 0.30, blue: 0.42, alpha: 1)
    )

    var activeChunkCount: Int { chunks.count }

    init() {
        rootNode.name = "road-stream-root"
    }

    func update(playerDistance: Double, mapper: TrackWorldMapper3D) {
        let startIndex = Int(floor((playerDistance - behindDistance) / chunkLength))
        let endIndex = Int(ceil((playerDistance + aheadDistance) / chunkLength))

        if mapper.routeVersion != lastRouteVersion {
            for node in chunks.values { node.removeFromParentNode() }
            chunks.removeAll(keepingCapacity: true)
            chunkOrigins.removeAll(keepingCapacity: true)
            lastRouteVersion = mapper.routeVersion
        }
        if mapper.originVersion != lastOriginVersion {
            // Chunks keep the geometry they were built with; translate them into the new origin space.
            let origin = mapper.originWorldPosition
            for (index, node) in chunks {
                if let buildOrigin = chunkOrigins[index] {
                    node.position = buildOrigin - origin
                }
            }
            lastOriginVersion = mapper.originVersion
        }

        for (index, node) in chunks where index < startIndex || index > endIndex {
            node.removeFromParentNode()
            chunks[index] = nil
            chunkOrigins[index] = nil
        }
        // A branch commits at a checkpoint and invalidates the route mesh. Keep that
        // frame bounded, and restore the road under the car before distant chunks.
        let playerChunk = Int(floor(playerDistance / chunkLength))
        let missing = (startIndex...endIndex)
            .filter { chunks[$0] == nil }
            .sorted { abs($0 - playerChunk) < abs($1 - playerChunk) }
        for index in missing.prefix(4) {
            let node = buildChunk(index: index, mapper: mapper)
            chunks[index] = node
            chunkOrigins[index] = mapper.originWorldPosition
            rootNode.addChildNode(node)
        }
    }

    private struct StripAccumulator {
        var vertices: [SCNVector3] = []
        var indicesByMaterial: [[Int32]]

        init(materialCount: Int) {
            indicesByMaterial = Array(repeating: [], count: materialCount)
        }
    }

    private enum Layer: Int, CaseIterable {
        case shoulder, asphalt, magenta, cyan, amber, offRoadGrid, surfaceGrid
    }

    private var layerMaterials: [SCNMaterial] {
        [shoulderMaterial, asphaltMaterial, magentaMaterial, cyanMaterial, amberMaterial, offRoadGridMaterial, surfaceGridMaterial]
    }

    private func buildChunk(index: Int, mapper: TrackWorldMapper3D) -> SCNNode {
        let start = Double(index) * chunkLength
        let end = start + chunkLength
        var accumulator = StripAccumulator(materialCount: Layer.allCases.count)

        // Sample the centerline once per chunk; every strip reuses these frames.
        var frames: [TrackWorldFrame3D] = []
        var distance = start
        while distance < end - 0.001 {
            frames.append(mapper.frame(atRunDistance: distance))
            distance += sampleSpacing
        }
        frames.append(mapper.frame(atRunDistance: end))

        func strip(
            _ layer: Layer,
            from: Double = start,
            to: Double = end,
            yOffset: Float,
            left: (TrackWorldFrame3D) -> Float,
            right: (TrackWorldFrame3D) -> Float
        ) {
            appendStrip(
                into: &accumulator,
                layer: layer,
                from: from,
                to: to,
                chunkStart: start,
                frames: frames,
                mapper: mapper,
                yOffset: yOffset,
                left: left,
                right: right
            )
        }

        func dashed(
            _ layer: Layer,
            dashLength: Double,
            gapLength: Double,
            yOffset: Float,
            left: @escaping (TrackWorldFrame3D) -> Float,
            right: @escaping (TrackWorldFrame3D) -> Float
        ) {
            let cycle = dashLength + gapLength
            var dashStart = floor(start / cycle) * cycle
            while dashStart < end {
                let from = max(start, dashStart)
                let to = min(end, dashStart + dashLength)
                if to - from > 0.05 {
                    strip(layer, from: from, to: to, yOffset: yOffset, left: left, right: right)
                }
                dashStart += cycle
            }
        }

        strip(.shoulder, yOffset: 0.0, left: { -Self.offRoadExtent(for: $0) }, right: { Self.offRoadExtent(for: $0) })
        strip(.asphalt, yOffset: 0.02, left: { -$0.roadHalfWidth }, right: { $0.roadHalfWidth })
        strip(.magenta, yOffset: 0.04, left: { -$0.roadHalfWidth - 0.12 }, right: { -$0.roadHalfWidth + 0.18 })
        strip(.magenta, yOffset: 0.04, left: { $0.roadHalfWidth - 0.18 }, right: { $0.roadHalfWidth + 0.12 })

        let midFrame = mapper.frame(atRunDistance: (start + end) * 0.5)
        if midFrame.laneCount > 1 {
            for lane in 1..<midFrame.laneCount {
                let normalized = Float(-1.0 + Double(lane) / Double(midFrame.laneCount) * 2.0)
                dashed(
                    midFrame.laneCount.isMultiple(of: 2) && lane == midFrame.laneCount / 2 ? .amber : .cyan,
                    dashLength: 8,
                    gapLength: 14,
                    yOffset: 0.04,
                    left: { normalized * $0.roadHalfWidth - 0.055 },
                    right: { normalized * $0.roadHalfWidth + 0.055 }
                )
            }
        }

        var latticeDistance = ceil(start / 6) * 6
        while latticeDistance < end {
            if latticeDistance.truncatingRemainder(dividingBy: 24) != 0 {
                strip(
                    .surfaceGrid,
                    from: latticeDistance,
                    to: min(latticeDistance + 0.12, end),
                    yOffset: 0.03,
                    left: { -$0.roadHalfWidth },
                    right: { $0.roadHalfWidth }
                )
            }
            latticeDistance += 6
        }
        for normalized in [Float(-0.75), -0.25, 0.25, 0.75] {
            strip(
                .surfaceGrid,
                yOffset: 0.03,
                left: { normalized * $0.roadHalfWidth - 0.03 },
                right: { normalized * $0.roadHalfWidth + 0.03 }
            )
        }

        var gridDistance = ceil(start / 24) * 24
        while gridDistance < end {
            strip(
                .cyan,
                from: gridDistance,
                to: min(gridDistance + 0.35, end),
                yOffset: 0.03,
                left: { -Self.offRoadExtent(for: $0) },
                right: { Self.offRoadExtent(for: $0) }
            )
            gridDistance += 24
        }

        for normalized in [Float(-1.6), -1.3, 1.3, 1.6] {
            dashed(
                .offRoadGrid,
                dashLength: 14,
                gapLength: 22,
                yOffset: 0.03,
                left: { normalized * $0.roadHalfWidth - 0.045 },
                right: { normalized * $0.roadHalfWidth + 0.045 }
            )
        }

        let materials = layerMaterials
        var elements: [SCNGeometryElement] = []
        var elementMaterials: [SCNMaterial] = []
        for (layerIndex, indices) in accumulator.indicesByMaterial.enumerated() where !indices.isEmpty {
            elements.append(SCNGeometryElement(indices: indices, primitiveType: .triangles))
            elementMaterials.append(materials[layerIndex])
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: accumulator.vertices)],
            elements: elements
        )
        geometry.materials = elementMaterials
        let node = SCNNode(geometry: geometry)
        node.name = "road-chunk-\(index)"
        node.castsShadow = false
        return node
    }

    private func appendStrip(
        into accumulator: inout StripAccumulator,
        layer: Layer,
        from: Double,
        to: Double,
        chunkStart: Double,
        frames: [TrackWorldFrame3D],
        mapper: TrackWorldMapper3D,
        yOffset: Float,
        left: (TrackWorldFrame3D) -> Float,
        right: (TrackWorldFrame3D) -> Float
    ) {
        // Row distances: strip endpoints plus any shared centerline samples in between.
        var rowFrames: [TrackWorldFrame3D] = [mapper.frame(atRunDistance: from)]
        for frame in frames where frame.runDistance > from + 0.01 && frame.runDistance < to - 0.01 {
            rowFrames.append(frame)
        }
        rowFrames.append(mapper.frame(atRunDistance: to))

        let base = Int32(accumulator.vertices.count)
        for frame in rowFrames {
            let leftPosition = frame.position + frame.right * left(frame)
            let rightPosition = frame.position + frame.right * right(frame)
            accumulator.vertices.append(SCNVector3(leftPosition.x, leftPosition.y + yOffset, leftPosition.z))
            accumulator.vertices.append(SCNVector3(rightPosition.x, rightPosition.y + yOffset, rightPosition.z))
        }
        for row in 1..<Int32(rowFrames.count) {
            let a = base + (row - 1) * 2
            accumulator.indicesByMaterial[layer.rawValue] += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
        }
    }

    private static func offRoadExtent(for frame: TrackWorldFrame3D) -> Float {
        max(frame.roadHalfWidth * 1.65, frame.roadHalfWidth + frame.shoulderWidth + 1.0)
    }

    private static func material(diffuse: UIColor, emission: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = diffuse
        material.emission.contents = emission
        material.lightingModel = .constant
        material.isDoubleSided = true
        return material
    }
}
