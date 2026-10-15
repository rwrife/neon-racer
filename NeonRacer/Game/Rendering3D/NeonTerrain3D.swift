import Foundation
import SceneKit
import UIKit

@MainActor
final class NeonTerrain3D {
    let rootNode = SCNNode()

    private struct TerrainQuality: Equatable {
        let chunkLength: Double
        let longitudinalSpacing: Double
        let lateralSpacing: Float
        let lateralExtent: Float
        let behindDistance: Double
        let aheadDistance: Double
        let chunksPerFrame: Int

        init(renderQuality: RenderQualityConfiguration) {
            let scenery = Float(renderQuality.sceneryDensityScale)
            chunkLength = renderQuality.tier == .low ? 84 : 72
            longitudinalSpacing = renderQuality.tier == .high ? 8 : (renderQuality.tier == .medium ? 10 : 13)
            lateralSpacing = renderQuality.tier == .high ? 18 : (renderQuality.tier == .medium ? 22 : 28)
            lateralExtent = max(170, min(360, Float(renderQuality.drawDistanceMeters) * (0.34 + scenery * 0.08)))
            behindDistance = renderQuality.tier == .low ? 120 : 150
            aheadDistance = renderQuality.drawDistanceMeters + 80
            chunksPerFrame = renderQuality.tier == .low ? 2 : 3
        }
    }

    private struct TerrainVertex {
        let position: SCNVector3
        let absolutePosition: SCNVector3
        let lateralOffset: Float
    }

    private struct TerrainMesh {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var fillIndices: [[Int32]] = Array(repeating: [], count: 3)
        var cyanLineIndices: [Int32] = []
        var magentaLineIndices: [Int32] = []
    }

    private var chunks: [Int: SCNNode] = [:]
    private var chunkOrigins: [Int: SCNVector3] = [:]
    private var pooledNodes: [SCNNode] = []
    private var lastOriginVersion = -1
    private var lastRouteVersion = -1
    private var lastQuality: TerrainQuality?
    private var materials: [SCNMaterial] = []
    private let seed: UInt32 = 0xC0FF_EE42

    var activeChunkCount: Int { chunks.count }

    init() {
        rootNode.name = "neon-low-poly-terrain-root"
    }

    func update(playerDistance: Double, mapper: TrackWorldMapper3D, renderQuality: RenderQualityConfiguration) {
        let terrainQuality = TerrainQuality(renderQuality: renderQuality)
        if terrainQuality != lastQuality {
            recycleAllChunks()
            materials = Self.makeMaterials(fadeEnd: Float(renderQuality.drawDistanceMeters + 110))
            lastQuality = terrainQuality
        } else if materials.isEmpty {
            materials = Self.makeMaterials(fadeEnd: Float(renderQuality.drawDistanceMeters + 110))
        }

        if mapper.routeVersion != lastRouteVersion {
            recycleAllChunks()
            lastRouteVersion = mapper.routeVersion
        }

        if mapper.originVersion != lastOriginVersion {
            let origin = mapper.originWorldPosition
            for (index, node) in chunks {
                if let buildOrigin = chunkOrigins[index] {
                    node.position = buildOrigin - origin
                }
            }
            lastOriginVersion = mapper.originVersion
        }

        let startIndex = max(0, Int(floor((playerDistance - terrainQuality.behindDistance) / terrainQuality.chunkLength)))
        let endIndex = max(startIndex, Int(ceil((playerDistance + terrainQuality.aheadDistance) / terrainQuality.chunkLength)))

        for (index, node) in chunks where index < startIndex || index > endIndex {
            recycle(node: node)
            chunks[index] = nil
            chunkOrigins[index] = nil
        }

        let wanted = Array(startIndex...endIndex)
            .filter { chunks[$0] == nil }
            .sorted { abs(chunkCenter($0, terrainQuality) - playerDistance) < abs(chunkCenter($1, terrainQuality) - playerDistance) }

        var built = 0
        for index in wanted {
            guard built < terrainQuality.chunksPerFrame else { break }
            let node = buildChunk(index: index, mapper: mapper, quality: terrainQuality)
            chunks[index] = node
            chunkOrigins[index] = mapper.originWorldPosition
            rootNode.addChildNode(node)
            built += 1
        }
    }

    private func chunkCenter(_ index: Int, _ quality: TerrainQuality) -> Double {
        (Double(index) + 0.5) * quality.chunkLength
    }

    private func recycleAllChunks() {
        for node in chunks.values {
            recycle(node: node)
        }
        chunks.removeAll(keepingCapacity: true)
        chunkOrigins.removeAll(keepingCapacity: true)
    }

    private func recycle(node: SCNNode) {
        node.removeFromParentNode()
        node.geometry = nil
        node.position = SCNVector3Zero
        if pooledNodes.count < 10 {
            pooledNodes.append(node)
        }
    }

    private func buildChunk(index: Int, mapper: TrackWorldMapper3D, quality: TerrainQuality) -> SCNNode {
        let start = Double(index) * quality.chunkLength
        let end = start + quality.chunkLength
        let lateralOffsets = Self.lateralOffsets(extent: quality.lateralExtent, spacing: quality.lateralSpacing)
        var rows: [[TerrainVertex]] = []
        var distance = start
        while distance < end - 0.001 {
            rows.append(buildRow(distance: distance, lateralOffsets: lateralOffsets, mapper: mapper, quality: quality))
            distance += quality.longitudinalSpacing
        }
        rows.append(buildRow(distance: end, lateralOffsets: lateralOffsets, mapper: mapper, quality: quality))

        var mesh = TerrainMesh()
        mesh.vertices.reserveCapacity(max(0, (rows.count - 1) * (lateralOffsets.count - 1) * 6))
        mesh.normals.reserveCapacity(mesh.vertices.capacity)

        for row in 0..<(rows.count - 1) {
            for column in 0..<(lateralOffsets.count - 1) {
                let p00 = rows[row][column]
                let p01 = rows[row][column + 1]
                let p10 = rows[row + 1][column]
                let p11 = rows[row + 1][column + 1]
                appendTriangle(p00, p10, p01, chunkIndex: index, into: &mesh)
                appendTriangle(p10, p11, p01, chunkIndex: index, into: &mesh)
            }
        }

        let elements = [
            SCNGeometryElement(indices: mesh.fillIndices[0], primitiveType: .triangles),
            SCNGeometryElement(indices: mesh.fillIndices[1], primitiveType: .triangles),
            SCNGeometryElement(indices: mesh.fillIndices[2], primitiveType: .triangles),
            SCNGeometryElement(indices: mesh.cyanLineIndices, primitiveType: .line),
            SCNGeometryElement(indices: mesh.magentaLineIndices, primitiveType: .line)
        ]

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: mesh.vertices),
                SCNGeometrySource(normals: mesh.normals)
            ],
            elements: elements
        )
        geometry.materials = materials

        let node = pooledNodes.popLast() ?? SCNNode()
        node.name = "neon-terrain-chunk-\(index)"
        node.geometry = geometry
        node.castsShadow = false
        node.renderingOrder = -900
        return node
    }

    private func buildRow(
        distance: Double,
        lateralOffsets: [Float],
        mapper: TrackWorldMapper3D,
        quality: TerrainQuality
    ) -> [TerrainVertex] {
        let frame = mapper.frame(atRunDistance: distance)
        let absoluteCenter = frame.position + mapper.originWorldPosition
        let cross = mapper.layout.splitCrossSection(stageID: frame.stageID, distanceInStage: frame.distanceInStage)
        // The terrain floor must clear the lower branch too, rather than burying
        // a descending road under the original centerline's flat apron.
        let roadFloor = frame.position.y + Float(min(cross?.leftElevation ?? 0, cross?.rightElevation ?? 0))
        let apron = max(frame.roadHalfWidth + frame.shoulderWidth + 5.0, frame.roadHalfWidth * 1.72 + 2.0)
        return lateralOffsets.map { lateral in
            let basePosition = frame.position + frame.right * lateral
            let absolutePosition = absoluteCenter + frame.right * lateral
            let y = height(
                roadY: roadFloor,
                absoluteX: absolutePosition.x,
                absoluteZ: absolutePosition.z,
                runDistance: Float(distance),
                lateralOffset: lateral,
                apron: apron,
                extent: quality.lateralExtent
            )
            let position = SCNVector3(basePosition.x, y, basePosition.z)
            return TerrainVertex(position: position, absolutePosition: SCNVector3(absolutePosition.x, y + mapper.originWorldPosition.y, absolutePosition.z), lateralOffset: lateral)
        }
    }

    private func height(
        roadY: Float,
        absoluteX: Float,
        absoluteZ: Float,
        runDistance: Float,
        lateralOffset: Float,
        apron: Float,
        extent: Float
    ) -> Float {
        let absLateral = abs(lateralOffset)
        let apronHeight = roadY - 0.58
        let blendWidth: Float = 58
        let blend = smoothstep(apron, apron + blendWidth, absLateral)
        let far = smoothstep(apron + 18, max(apron + blendWidth, extent), absLateral)
        let side: Float = lateralOffset < 0 ? -1 : 1
        let broad = valueNoise(x: absoluteX, z: absoluteZ, scale: 190) - 0.5
        let medium = valueNoise(x: absoluteX + 131.7, z: absoluteZ - 43.2, scale: 82) - 0.5
        let fine = valueNoise(x: absoluteX - 19.4, z: absoluteZ + 97.1, scale: 34) - 0.5
        let ridgeNoise = 1.0 - abs(valueNoise(x: absoluteX * 0.55 + side * 80, z: absoluteZ * 0.72, scale: 145) * 2.0 - 1.0)
        let ridge = pow(max(0, ridgeNoise), 2.1)
        let wave = sin(runDistance * 0.018 + side * 1.7 + broad * 2.8)
        let amplitude = 5.5 + far * 30.0
        let rolling = broad * amplitude + medium * (5.0 + far * 13.0) + fine * (1.0 + far * 2.8)
        let ridges = (ridge * (7.0 + far * 28.0) + wave * (2.5 + far * 8.5)) * far
        let outerHeight = roadY - 2.2 + rolling + ridges
        return mix(apronHeight, outerHeight, blend)
    }

    private func appendTriangle(
        _ a: TerrainVertex,
        _ b: TerrainVertex,
        _ c: TerrainVertex,
        chunkIndex: Int,
        into mesh: inout TerrainMesh
    ) {
        let pa = a.position
        var pb = b.position
        var pc = c.position
        var normal = Self.normal(pa, pb, pc)
        if normal.y < 0 {
            swap(&pb, &pc)
            normal = normal * -1
        }

        let base = Int32(mesh.vertices.count)
        mesh.vertices += [pa, pb, pc]
        mesh.normals += [normal, normal, normal]

        let centerX = (a.absolutePosition.x + b.absolutePosition.x + c.absolutePosition.x) / 3
        let centerZ = (a.absolutePosition.z + b.absolutePosition.z + c.absolutePosition.z) / 3
        let centerLateral = (a.lateralOffset + b.lateralOffset + c.lateralOffset) / 3
        let shade = valueNoise(x: centerX, z: centerZ, scale: 44)
        let slope = 1 - min(max(normal.y, 0), 1)
        let materialIndex = min(2, max(0, Int((shade * 1.7 + slope * 2.4).rounded(.down))))
        mesh.fillIndices[materialIndex] += [base, base + 1, base + 2]

        let lineIndices = [base, base + 1, base + 1, base + 2, base + 2, base]
        let stripe = Int(abs(centerX) * 0.07 + abs(centerZ) * 0.05 + abs(centerLateral) * 0.21) + chunkIndex
        if stripe.isMultiple(of: 4) {
            mesh.magentaLineIndices += lineIndices
        } else {
            mesh.cyanLineIndices += lineIndices
        }
    }

    private static func lateralOffsets(extent: Float, spacing: Float) -> [Float] {
        var offsets: [Float] = []
        var lateral = -extent
        while lateral < extent - 0.001 {
            offsets.append(lateral)
            lateral += spacing
        }
        offsets.append(extent)
        if !offsets.contains(where: { abs($0) < 0.001 }) {
            offsets.append(0)
            offsets.sort()
        }
        return offsets
    }

    private static func normal(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3) -> SCNVector3 {
        let u = b - a
        let v = c - a
        let crossed = SCNVector3(
            u.y * v.z - u.z * v.y,
            u.z * v.x - u.x * v.z,
            u.x * v.y - u.y * v.x
        )
        let length = max(crossed.length, 0.0001)
        return crossed * (1 / length)
    }

    private func valueNoise(x: Float, z: Float, scale: Float) -> Float {
        let sx = x / scale
        let sz = z / scale
        let ix = Int32(floor(sx))
        let iz = Int32(floor(sz))
        let fx = sx - Float(ix)
        let fz = sz - Float(iz)
        let tx = fx * fx * (3 - 2 * fx)
        let tz = fz * fz * (3 - 2 * fz)
        let n00 = hash(ix, iz)
        let n10 = hash(ix + 1, iz)
        let n01 = hash(ix, iz + 1)
        let n11 = hash(ix + 1, iz + 1)
        return mix(mix(n00, n10, tx), mix(n01, n11, tx), tz)
    }

    private func hash(_ x: Int32, _ z: Int32) -> Float {
        var h = (UInt32(bitPattern: x) &* 374_761_393) &+ (UInt32(bitPattern: z) &* 668_265_263) &+ seed
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0x00FF_FFFF) / Float(0x00FF_FFFF)
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let denominator = max(edge1 - edge0, 0.0001)
        let t = min(max((value - edge0) / denominator, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    private static func makeMaterials(fadeEnd: Float) -> [SCNMaterial] {
        let fadeStart = max(80, fadeEnd * 0.24)
        let fillColors = [
            UIColor(red: 0.045, green: 0.014, blue: 0.105, alpha: 1),
            UIColor(red: 0.070, green: 0.020, blue: 0.155, alpha: 1),
            UIColor(red: 0.105, green: 0.030, blue: 0.195, alpha: 1)
        ]
        let fillEmissions = [
            UIColor(red: 0.010, green: 0.002, blue: 0.030, alpha: 1),
            UIColor(red: 0.018, green: 0.003, blue: 0.045, alpha: 1),
            UIColor(red: 0.032, green: 0.004, blue: 0.065, alpha: 1)
        ]
        let fills = zip(fillColors, fillEmissions).map { color, emission in
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = emission
            material.lightingModel = .lambert
            material.isDoubleSided = true
            material.writesToDepthBuffer = true
            material.shaderModifiers = [.fragment: fadeShader(fadeStart: fadeStart, fadeEnd: fadeEnd)]
            return material
        }
        let cyan = lineMaterial(
            color: UIColor(red: 0.0, green: 0.96, blue: 1.0, alpha: 1),
            fadeStart: fadeStart,
            fadeEnd: fadeEnd
        )
        let magenta = lineMaterial(
            color: UIColor(red: 1.0, green: 0.05, blue: 0.78, alpha: 1),
            fadeStart: fadeStart,
            fadeEnd: fadeEnd
        )
        return fills + [cyan, magenta]
    }

    private static func lineMaterial(color: UIColor, fadeStart: Float, fadeEnd: Float) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.transparency = 0.82
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.shaderModifiers = [.fragment: fadeShader(fadeStart: fadeStart, fadeEnd: fadeEnd)]
        return material
    }

    private static func fadeShader(fadeStart: Float, fadeEnd: Float) -> String {
        """
        #pragma body
        float nrTerrainFade = 1.0 - smoothstep(\(fadeStart), \(fadeEnd), length(_surface.position));
        _output.color *= nrTerrainFade;
        """
    }
}
