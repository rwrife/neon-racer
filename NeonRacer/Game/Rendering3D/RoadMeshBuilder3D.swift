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

/// Bounded, preloaded tunnel mesh in the road's existing world space. The open
/// portals and continuous road surface avoid a scene switch at either end.
@MainActor
final class TunnelMeshBuilder3D {
    let rootNode = SCNNode()
    private var nodes: [String: SCNNode] = [:]
    private var origins: [String: SCNVector3] = [:]
    private var originVersion = -1
    private var routeVersion = -1
    private let panel = TunnelMeshBuilder3D.material(UIColor(red: 0.025, green: 0.015, blue: 0.055, alpha: 1))
    private let cyan = TunnelMeshBuilder3D.material(UIColor(red: 0.02, green: 0.7, blue: 0.85, alpha: 1))
    private let violet = TunnelMeshBuilder3D.material(UIColor(red: 0.55, green: 0.08, blue: 0.8, alpha: 1))
    var activeSegmentCount: Int { nodes.count }

    init() { rootNode.name = "continuous-tunnel-root" }

    func update(playerDistance: Double, mapper: TrackWorldMapper3D) {
        if routeVersion != mapper.routeVersion {
            nodes.values.forEach { $0.removeFromParentNode() }
            nodes.removeAll()
            origins.removeAll()
            routeVersion = mapper.routeVersion
        }
        if originVersion != mapper.originVersion {
            for (key, node) in nodes { node.position = origins[key]! - mapper.originWorldPosition }
            originVersion = mapper.originVersion
        }
        var wanted: Set<String> = []
        var newSegments = 0
        for placement in mapper.placements {
            guard let tunnel = mapper.layout.tunnel(for: placement.stage.id) else { continue }
            var local = tunnel.entrance
            while local < tunnel.exit {
                let from = placement.startRunDistance + local
                let to = min(from + 24, placement.startRunDistance + tunnel.exit)
                let key = "\(placement.stage.id)-\(Int(local))"
                if to > playerDistance - 120 && from < playerDistance + 840 {
                    wanted.insert(key)
                    if nodes[key] == nil && newSegments < 4 {
                        let node = build(from: from, to: to, height: Float(tunnel.ceilingHeight),
                                         entrance: local == tunnel.entrance,
                                         exit: to == placement.startRunDistance + tunnel.exit, mapper: mapper)
                        node.name = "tunnel-segment-\(key)"
                        nodes[key] = node
                        origins[key] = mapper.originWorldPosition
                        rootNode.addChildNode(node)
                        newSegments += 1
                    }
                }
                local += 24
            }
        }
        for key in Array(nodes.keys) where !wanted.contains(key) {
            nodes.removeValue(forKey: key)?.removeFromParentNode()
            origins[key] = nil
        }
    }

    private func build(from: Double, to: Double, height: Float, entrance: Bool, exit: Bool,
                       mapper: TrackWorldMapper3D) -> SCNNode {
        let root = SCNNode()
        var frames: [TrackWorldFrame3D] = []
        var distance = from
        while distance < to { frames.append(mapper.frame(atRunDistance: distance)); distance += 6 }
        frames.append(mapper.frame(atRunDistance: to))
        func point(_ frame: TrackWorldFrame3D, side: Float, y: Float) -> SCNVector3 {
            frame.position + frame.right * (side * (frame.roadHalfWidth + 1.0)) + SCNVector3(0, y, 0)
        }
        func ribbon(name: String, material: SCNMaterial,
                    left: (TrackWorldFrame3D) -> SCNVector3,
                    right: (TrackWorldFrame3D) -> SCNVector3) {
            var vertices: [SCNVector3] = []
            var indices: [Int32] = []
            for frame in frames { vertices += [left(frame), right(frame)] }
            for row in 1..<frames.count {
                let a = Int32((row - 1) * 2)
                indices += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
            }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                       elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = name
            root.addChildNode(node)
        }
        ribbon(name: "tunnel-ceiling", material: panel,
               left: { point($0, side: -1, y: height) }, right: { point($0, side: 1, y: height) })
        for side: Float in [-1, 1] {
            ribbon(name: "tunnel-wall", material: panel,
                   left: { point($0, side: side, y: 0) }, right: { point($0, side: side, y: height) })
            for y: Float in [0.65, height - 0.45] {
                ribbon(name: "tunnel-neon-wall-rail", material: side < 0 ? cyan : violet,
                       left: { point($0, side: side * 0.997, y: y) },
                       right: { point($0, side: side * 0.997, y: y + 0.07) })
            }
            let frame = frames[frames.count / 2]
            let text = SCNText(string: side < 0 ? "AXIS  ››" : "KEEP MOVING  ››", extrusionDepth: 0.005)
            text.font = UIFont.monospacedSystemFont(ofSize: 0.45, weight: .bold)
            text.flatness = 0.15
            text.materials = [side < 0 ? cyan : violet]
            let sign = SCNNode(geometry: text)
            sign.name = "tunnel-wall-neon-sign"
            sign.position = point(frame, side: side * 0.985, y: 2.2)
            sign.eulerAngles.y = frame.yaw + (side < 0 ? .pi / 2 : -.pi / 2)
            root.addChildNode(sign)
        }
        // Repeating overhead light strips provide depth and speed cues without flashing.
        let frame = frames[0]
        let beam = SCNNode(geometry: SCNBox(width: CGFloat(frame.roadHalfWidth * 2 + 2),
                                          height: 0.07, length: 0.15, chamferRadius: 0))
        beam.geometry?.materials = [cyan]
        beam.position = frame.position + SCNVector3(0, height - 0.1, 0)
        beam.eulerAngles = SCNVector3(frame.pitch, frame.yaw, 0)
        beam.name = "tunnel-overhead-light"
        root.addChildNode(beam)
        if entrance || exit {
            let portalFrame = entrance ? frames[0] : frames.last!
            let text = SCNText(string: entrance ? "AXIS TUNNEL" : "EXIT", extrusionDepth: 0.01)
            text.font = UIFont.monospacedSystemFont(ofSize: 0.65, weight: .bold)
            text.materials = [cyan]
            let label = SCNNode(geometry: text)
            let bounds = text.boundingBox
            label.pivot = SCNMatrix4MakeTranslation((bounds.min.x + bounds.max.x) / 2, 0, 0)
            label.position = portalFrame.position + SCNVector3(0, height + 0.15, 0)
            label.eulerAngles.y = portalFrame.yaw
            label.name = entrance ? "tunnel-entrance-sign" : "tunnel-exit-sign"
            root.addChildNode(label)
        }
        return root
    }

    private static func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        return material
    }
}
