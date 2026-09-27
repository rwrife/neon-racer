import Foundation
import SceneKit
import simd
import UIKit

@MainActor
final class TrackMarkers3D {
    let rootNode = SCNNode()
    private var markerNodes: [String: SCNNode] = [:]
    private var lightNodes: [SCNNode] = []
    private let cyan = TrackMarkers3D.material(.cyan)
    private let magenta = TrackMarkers3D.material(.magenta)
    private let green = TrackMarkers3D.material(.green)
    private let red = TrackMarkers3D.material(.red)
    private let orange = TrackMarkers3D.material(.orange)
    private let white = TrackMarkers3D.material(.white)
    private let black = TrackMarkers3D.material(.black)
    private let hotPink = TrackMarkers3D.material(UIColor(red: 1, green: 0.08, blue: 0.55, alpha: 1))
    private let startLattice = TrackMarkers3D.material(UIColor(red: 0, green: 0.55, blue: 0.7, alpha: 1))
    private let darkPanel = TrackMarkers3D.material(UIColor(red: 0.015, green: 0.0, blue: 0.045, alpha: 1), emission: UIColor(red: 0.04, green: 0.0, blue: 0.08, alpha: 1))

    init() {
        rootNode.name = "track-markers-root"
    }

    func update(state: RaceState, mapper: TrackWorldMapper3D) {
        var activeKeys: Set<String> = []
        for placement in mapper.placements {
            for marker in mapper.layout.markers(for: placement.stage.id) {
                guard let runDistance = mapper.runDistance(stageID: marker.stageID, distanceInStage: marker.distanceInStage),
                      runDistance > state.distance - 80,
                      runDistance < state.distance + 850 else { continue }
                let key = "\(marker.kind.rawValue)-\(marker.stageID)-\(Int(marker.distanceInStage))"
                activeKeys.insert(key)
                let node = markerNodes[key] ?? makeMarker(marker, routeStage: placement.stage)
                markerNodes[key] = node
                if node.parent == nil { rootNode.addChildNode(node) }
                let frame = mapper.frame(atRunDistance: runDistance)
                node.position = frame.position
                node.eulerAngles = SCNVector3(frame.pitch, frame.yaw, 0)
            }
        }
        for (key, node) in markerNodes where !activeKeys.contains(key) {
            node.removeFromParentNode()
        }
        updateCountdownLights(state: state)
    }

    private func makeMarker(_ marker: TrackZoneMarker, routeStage: RouteStage) -> SCNNode {
        switch marker.kind {
        case .startGrid:
            return makeStartGrid()
        case .startLine:
            return makeMonumentalStartGantry()
        case .checkpoint:
            return makeArch(title: "CHECK", material: magenta, height: 7, width: 15, includeLights: false)
        case .forkSplit:
            return makeForkSign(stage: routeStage)
        case .finishLine:
            return makeMonumentalFinishGantry()
        }
    }

    private func makeStartGrid() -> SCNNode {
        let node = SCNNode()
        let asphalt = SCNNode(geometry: SCNBox(width: 22, height: 0.03, length: 150, chamferRadius: 0))
        asphalt.name = "start-view-dark-violet-asphalt-panel"
        asphalt.geometry?.materials = [darkPanel]
        asphalt.position = SCNVector3(0, 0.025, -64)
        node.addChildNode(asphalt)
        for x in stride(from: -10.0, through: 10.0, by: 2.0) {
            let line = SCNNode(geometry: SCNBox(width: 0.045, height: 0.045, length: 150, chamferRadius: 0.006))
            line.name = "start-cyan-grid-longitudinal"
            line.geometry?.materials = [startLattice]
            line.position = SCNVector3(Float(x), 0.08, -64)
            node.addChildNode(line)
        }
        for z in stride(from: 6.0, through: -136.0, by: -8.0) {
            let line = SCNNode(geometry: SCNBox(width: 22, height: 0.045, length: 0.06, chamferRadius: 0.006))
            line.name = "start-cyan-grid-cross"
            line.geometry?.materials = [startLattice]
            line.position = SCNVector3(0, 0.085, Float(z))
            node.addChildNode(line)
        }
        for x in [-7.2 as Float, 7.2] {
            let edge = SCNNode(geometry: SCNBox(width: 0.18, height: 0.075, length: 150, chamferRadius: 0.02))
            edge.name = "start-magenta-edge-strip"
            edge.geometry?.materials = [magenta]
            edge.position = SCNVector3(x, 0.12, -64)
            node.addChildNode(edge)
        }
        // Staggered starting-grid slots drawn as thin neon brackets.
        for row in 0..<4 {
            let x: Float = row.isMultiple(of: 2) ? -2.4 : 2.4
            let z = Float(row) * 9.0 + 7.5
            let slotMaterial = row.isMultiple(of: 2) ? cyan : magenta
            let front = SCNNode(geometry: SCNBox(width: 2.6, height: 0.05, length: 0.16, chamferRadius: 0))
            front.geometry?.materials = [slotMaterial]
            front.position = SCNVector3(x, 0.09, z - 2.4)
            node.addChildNode(front)
            for side in [-1.3 as Float, 1.3] {
                let rail = SCNNode(geometry: SCNBox(width: 0.12, height: 0.05, length: 1.6, chamferRadius: 0))
                rail.geometry?.materials = [slotMaterial]
                rail.position = SCNVector3(x + side, 0.09, z - 1.6)
                node.addChildNode(rail)
            }
        }
        let flattened = node.flattenedClone()
        flattened.name = "start-grid-flattened"
        return flattened
    }

    private func makeArch(title: String, material: SCNMaterial, height: CGFloat, width: CGFloat, includeLights: Bool) -> SCNNode {
        let node = SCNNode()
        let left = post(height: height, material: material)
        left.position.x = Float(-width / 2)
        let right = post(height: height, material: material)
        right.position.x = Float(width / 2)
        let top = SCNNode(geometry: SCNBox(width: width + 1.6, height: 0.45, length: 0.45, chamferRadius: 0.08))
        top.geometry?.materials = [material]
        top.position.y = Float(height)
        node.addChildNode(left)
        node.addChildNode(right)
        node.addChildNode(top)
        let text = textNode(title, size: 1.35, material: material)
        text.position = SCNVector3(0, Float(height + 1.2), 0.1)
        node.addChildNode(text)
        if includeLights {
            lightNodes.removeAll(keepingCapacity: true)
            for index in 0..<3 {
                let light = SCNNode(geometry: SCNSphere(radius: 0.38))
                light.geometry?.materials = [red]
                light.position = SCNVector3(Float(index - 1) * 1.25, Float(height - 0.95), -0.35)
                lightNodes.append(light)
                node.addChildNode(light)
            }
        }
        return node
    }


    private func makeMonumentalStartGantry() -> SCNNode {
        makeMonumentalGantry(title: "START", isFinish: false)
    }

    private func makeMonumentalFinishGantry() -> SCNNode {
        makeMonumentalGantry(title: "FINISH", isFinish: true)
    }

    private func makeMonumentalGantry(title: String, isFinish: Bool) -> SCNNode {
        let node = SCNNode()
        node.name = isFinish ? "monumental-angular-finish-gantry" : "monumental-angular-start-gantry"
        let width: CGFloat = isFinish ? 23.2 : 24.8
        let height: CGFloat = isFinish ? 10.0 : 10.9
        let panel = SCNNode(geometry: SCNBox(width: width - 4.0, height: 3.45, length: 0.22, chamferRadius: 0.12))
        panel.name = "\(title.lowercased())-dark-glass-sign-panel"
        panel.geometry?.materials = [darkPanel]
        panel.position = SCNVector3(0, Float(height - 2.08), -0.98)
        panel.renderingOrder = -20
        node.addChildNode(panel)

        let leftFoot = SCNVector3(Float(-width / 2), 0, 0)
        let rightFoot = SCNVector3(Float(width / 2), 0, 0)
        let leftShoulder = SCNVector3(Float(-width / 2 + 3.1), Float(height), 0)
        let rightShoulder = SCNVector3(Float(width / 2 - 3.1), Float(height), 0)
        addBeam(to: node, name: "\(title.lowercased())-outer-left-cyan-tube", from: leftFoot, to: leftShoulder, radius: 0.34, material: cyan)
        addBeam(to: node, name: "\(title.lowercased())-outer-right-magenta-tube", from: rightFoot, to: rightShoulder, radius: 0.34, material: magenta)
        addBeam(to: node, name: "\(title.lowercased())-inner-left-magenta-tube", from: SCNVector3(leftFoot.x + 1.25, 0.95, -0.16), to: SCNVector3(leftShoulder.x + 0.70, leftShoulder.y - 0.95, -0.16), radius: 0.075, material: hotPink)
        addBeam(to: node, name: "\(title.lowercased())-inner-right-cyan-tube", from: SCNVector3(rightFoot.x - 1.25, 0.95, -0.16), to: SCNVector3(rightShoulder.x - 0.70, rightShoulder.y - 0.95, -0.16), radius: 0.075, material: cyan)
        addBeam(to: node, name: "\(title.lowercased())-top-left-cyan-truss", from: leftShoulder, to: SCNVector3(-0.2, Float(height), 0), radius: 0.30, material: cyan)
        addBeam(to: node, name: "\(title.lowercased())-top-right-magenta-truss", from: SCNVector3(0.2, Float(height), 0), to: rightShoulder, radius: 0.30, material: magenta)
        addBeam(to: node, name: "\(title.lowercased())-top-inner-hot-pink-outline", from: SCNVector3(leftShoulder.x + 1.0, leftShoulder.y - 0.64, -0.18), to: SCNVector3(rightShoulder.x - 1.0, rightShoulder.y - 0.64, -0.18), radius: 0.075, material: hotPink)
        addBeam(to: node, name: "\(title.lowercased())-overhead-cyan-lightbar", from: SCNVector3(-6.9, Float(height - 1.05), -0.42), to: SCNVector3(6.9, Float(height - 1.05), -0.42), radius: 0.078, material: cyan)
        addBeam(to: node, name: "\(title.lowercased())-lower-hot-pink-tube", from: SCNVector3(-8.4, Float(height - 3.98), -0.46), to: SCNVector3(8.4, Float(height - 3.98), -0.46), radius: 0.058, material: hotPink)
        for x in [-8.8 as Float, 8.8] {
            addBeam(to: node, name: "\(title.lowercased())-short-panel-upright", from: SCNVector3(x, Float(height - 3.78), -0.44), to: SCNVector3(x, Float(height - 0.72), -0.44), radius: 0.045, material: x < 0 ? cyan : magenta)
        }

        let mainText = textNode(title, size: isFinish ? 1.82 : 2.15, material: hotPink)
        mainText.name = "huge-hot-pink-outlined-\(title.lowercased())-tube-lettering"
        mainText.position = SCNVector3(isFinish ? 0.18 : 0, Float(height - 2.18), -0.52)
        mainText.renderingOrder = 20
        node.addChildNode(mainText)
        let cyanOutline = textNode(title, size: isFinish ? 1.90 : 2.24, material: cyan)
        cyanOutline.name = "\(title.lowercased())-cyan-outer-glow-lettering"
        cyanOutline.opacity = 0.22
        cyanOutline.position = SCNVector3(isFinish ? 0.18 : 0, Float(height - 2.18), -0.60)
        cyanOutline.renderingOrder = 18
        node.addChildNode(cyanOutline)
        let magentaOutline = textNode(title, size: isFinish ? 1.98 : 2.32, material: magenta)
        magentaOutline.name = "\(title.lowercased())-magenta-halo-lettering"
        magentaOutline.opacity = 0.16
        magentaOutline.position = SCNVector3(isFinish ? 0.18 : 0, Float(height - 2.18), -0.66)
        magentaOutline.renderingOrder = 16
        node.addChildNode(magentaOutline)

        let emblem = makeWingedHelmetEmblem()
        emblem.position = SCNVector3(isFinish ? -8.9 : -8.65, Float(height - 2.72), -0.50)
        node.addChildNode(emblem)

        let pod = SCNNode(geometry: SCNBox(width: 1.2, height: 3.5, length: 0.35, chamferRadius: 0.12))
        pod.name = "\(title.lowercased())-vertical-countdown-light-pod"
        pod.geometry?.materials = [darkPanel]
        pod.position = SCNVector3(Float(-width / 2 + 1.75), 4.2, -0.45)
        node.addChildNode(pod)
        if !isFinish { lightNodes.removeAll(keepingCapacity: true) }
        for (index, material) in [hotPink, orange, cyan].enumerated() {
            let light = SCNNode(geometry: SCNBox(width: 0.66, height: 0.66, length: 0.09, chamferRadius: 0.09))
            light.name = "\(title.lowercased())-countdown-lamp-\(index)"
            light.geometry?.materials = [material]
            light.position = SCNVector3(0, Float(1.05 - Double(index) * 1.05), 0.22)
            if !isFinish { lightNodes.append(light) }
            pod.addChildNode(light)
        }

        addBillboardCluster(to: node, side: -1, x: -15.8, finish: isFinish)
        addBillboardCluster(to: node, side: 1, x: 15.8, finish: isFinish)
        for child in node.childNodes {
            child.position.z -= isFinish ? 15.0 : 18.0
        }
        let stripe = makeCheckeredStripe(width: isFinish ? 15.0 : 13.8, depth: isFinish ? 4.8 : 3.6)
        stripe.name = isFinish ? "finish-wide-checkered-neon-line" : "start-wide-checkered-neon-line"
        node.addChildNode(stripe)
        return node
    }

    private func makeWingedHelmetEmblem() -> SCNNode {
        let node = SCNNode()
        node.name = "original-low-poly-winged-helmet-emblem"
        let helmet = SCNNode(geometry: SCNBox(width: 1.35, height: 1.0, length: 0.16, chamferRadius: 0.18))
        helmet.geometry?.materials = [hotPink]
        node.addChildNode(helmet)
        let visor = SCNNode(geometry: SCNBox(width: 0.78, height: 0.22, length: 0.18, chamferRadius: 0.04))
        visor.geometry?.materials = [darkPanel]
        visor.position = SCNVector3(0.18, 0.06, 0.1)
        node.addChildNode(visor)
        for side in [-1.0, 1.0] {
            for wing in 0..<3 {
                let feather = SCNNode(geometry: SCNBox(width: 0.72 - CGFloat(wing) * 0.12, height: 0.12, length: 0.10, chamferRadius: 0.03))
                feather.geometry?.materials = [side < 0 ? cyan : magenta]
                feather.position = SCNVector3(Float(side) * Float(0.82 + Double(wing) * 0.36), Float(0.26 - Double(wing) * 0.18), -0.08)
                feather.eulerAngles.z = Float(side) * -0.34
                node.addChildNode(feather)
            }
        }
        return node
    }

    private func addBillboardCluster(to node: SCNNode, side: Double, x: Float, finish: Bool) {
        let ads = side < 0
            ? ["JPC\nBIOMEDICAL", "RE-GEN:\nRECLAIM YOUR\nPOTENTIAL", "CONSUME\nPRODUCT X"]
            : ["M. ALEE (Race Ldr)\nC. CORE\nT. REK   13:39", "OBEY\nCORPORATE\nDIKTAT", "EYE-NET\nIS ALWAYS\nWATCHING"]
        for (index, copy) in ads.enumerated() {
            let accent = index.isMultiple(of: 2) ? cyan : (side < 0 ? hotPink : orange)
            let panel = copy.contains("Race Ldr")
                ? makeHoloBillboard(copy, accent: orange, width: 4.9, height: 1.55, textSize: 0.24)
                : makeHoloBillboard(copy, accent: accent, width: index == 0 && side < 0 ? 3.5 : 4.1, height: 1.46, textSize: 0.25)
            let finishYOffset: Float = finish ? 0.45 : 0
            panel.position = SCNVector3(x, Float(2.25 + Double(index) * 1.70) + finishYOffset, Float(-4.2 - Double(index) * 3.55))
            panel.eulerAngles.y = Float(side) * 0.25
            node.addChildNode(panel)
        }
    }

    private func makeHoloBillboard(_ copy: String, accent: SCNMaterial, width: CGFloat = 3.7, height: CGFloat = 1.35, textSize: CGFloat = 0.28) -> SCNNode {
        let node = SCNNode()
        node.name = "start-holo-billboard-\(copy.replacingOccurrences(of: "\n", with: "-"))"
        let panel = SCNNode(geometry: SCNBox(width: width, height: height, length: 0.10, chamferRadius: 0.06))
        panel.geometry?.materials = [darkPanel]
        panel.position.z = -0.035
        panel.renderingOrder = -10
        node.addChildNode(panel)
        let halfWidth = Float(width / 2 + 0.10)
        let halfHeight = Float(height / 2 + 0.10)
        addBeam(to: node, name: "billboard-top", from: SCNVector3(-halfWidth, halfHeight, 0.08), to: SCNVector3(halfWidth, halfHeight, 0.08), radius: 0.035, material: accent)
        addBeam(to: node, name: "billboard-bottom", from: SCNVector3(-halfWidth, -halfHeight, 0.08), to: SCNVector3(halfWidth, -halfHeight, 0.08), radius: 0.035, material: accent)
        addBeam(to: node, name: "billboard-left", from: SCNVector3(-halfWidth, -halfHeight, 0.08), to: SCNVector3(-halfWidth, halfHeight, 0.08), radius: 0.035, material: accent)
        addBeam(to: node, name: "billboard-right", from: SCNVector3(halfWidth, -halfHeight, 0.08), to: SCNVector3(halfWidth, halfHeight, 0.08), radius: 0.035, material: accent)
        let label = textNode(copy, size: textSize, material: accent)
        label.position = SCNVector3(0, 0, 0.13)
        label.renderingOrder = 12
        node.addChildNode(label)
        return node
    }

    private func addBeam(to node: SCNNode, name: String, from: SCNVector3, to: SCNVector3, radius: CGFloat, material: SCNMaterial) {
        let vector = to - from
        let length = CGFloat(vector.length)
        guard length > 0 else { return }
        let beam = SCNNode(geometry: SCNCylinder(radius: radius, height: length))
        beam.name = name
        beam.geometry?.materials = [material]
        beam.position = (from + to) * 0.5
        beam.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(vector.x, vector.y, vector.z) / Float(length))
        node.addChildNode(beam)
    }

    private func makeForkSign(stage: RouteStage) -> SCNNode {
        let node = SCNNode()
        let panel = SCNNode(geometry: SCNBox(width: 13, height: 4.2, length: 0.25, chamferRadius: 0.08))
        panel.geometry?.materials = [TrackMarkers3D.material(UIColor(red: 0.02, green: 0, blue: 0.05, alpha: 1))]
        panel.position.y = 4.2
        node.addChildNode(panel)
        let left = stage.branches.first { $0.direction == .left } ?? stage.branches.first
        let right = stage.branches.first { $0.direction == .right } ?? stage.branches.dropFirst().first ?? stage.branches.first
        let leftText = textNode("← \(left?.previewName.uppercased() ?? "LEFT")", size: 0.55, material: cyan)
        leftText.position = SCNVector3(0, 5.1, 0.2)
        let rightText = textNode("\(right?.previewName.uppercased() ?? "RIGHT") →", size: 0.55, material: magenta)
        rightText.position = SCNVector3(0, 3.4, 0.2)
        node.addChildNode(leftText)
        node.addChildNode(rightText)
        node.addChildNode(post(height: 4.0, material: cyan))
        return node
    }

    private func makeCheckeredStripe(width: CGFloat, depth: CGFloat) -> SCNNode {
        let node = SCNNode()
        for row in 0..<2 {
            for column in 0..<8 {
                let tile = SCNNode(geometry: SCNBox(width: width / 8, height: 0.04, length: depth / 2, chamferRadius: 0))
                tile.geometry?.materials = [(row + column).isMultiple(of: 2) ? white : black]
                tile.position = SCNVector3(Float(-width / 2 + width / 16 + CGFloat(column) * width / 8), 0.08, Float(-depth / 2 + depth / 4 + CGFloat(row) * depth / 2))
                node.addChildNode(tile)
            }
        }
        return node
    }

    private func post(height: CGFloat, material: SCNMaterial) -> SCNNode {
        let node = SCNNode(geometry: SCNCylinder(radius: 0.18, height: height))
        node.geometry?.materials = [material]
        node.position.y = Float(height / 2)
        return node
    }

    private func textNode(_ string: String, size: CGFloat, material: SCNMaterial) -> SCNNode {
        let text = SCNText(string: string, extrusionDepth: 0.05)
        text.font = UIFont.boldSystemFont(ofSize: 1)
        text.flatness = 0.08
        text.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        text.materials = [material]
        let node = SCNNode(geometry: text)
        let (minBound, maxBound) = text.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((minBound.x + maxBound.x) / 2, (minBound.y + maxBound.y) / 2, 0)
        node.scale = SCNVector3(Float(size), Float(size), Float(size))
        return node
    }

    private func updateCountdownLights(state: RaceState) {
        guard !lightNodes.isEmpty else { return }
        if state.phase == .racing || state.phase == .fork || state.phase == .checkpoint {
            for light in lightNodes { light.geometry?.materials = [cyan] }
        } else {
            let active = max(0, min(2, 3 - Int(ceil(state.countdownRemaining))))
            for (index, light) in lightNodes.enumerated() {
                let litMaterial: SCNMaterial = switch index {
                case 0: hotPink
                case 1: orange
                default: cyan
                }
                light.geometry?.materials = [index <= active ? litMaterial : black]
            }
        }
    }

    private static func material(_ color: UIColor, emission: UIColor? = nil) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = emission ?? color
        material.lightingModel = .constant
        material.isDoubleSided = true
        return material
    }
}
