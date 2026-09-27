import SceneKit
import UIKit

@MainActor
final class NeonCarNode: SCNNode {
    private let animatedRoot = SCNNode()
    private let bodyYawNode = SCNNode()
    private var frontAxleNodes: [SCNNode] = []
    private var wheelAxleNodes: [SCNNode] = []
    private var wheelSpinNodes: [SCNNode] = []
    private var brakeLightMaterials: [SCNMaterial] = []
    private var boostFlameNodes: [SCNNode] = []
    private var boostMaterials: [SCNMaterial] = []
    private var underglowLight: SCNLight?
    private var underglowMaterial: SCNMaterial?
    private var baseRideHeight: Float = 0

    nonisolated override init() {
        super.init()
    }

    nonisolated required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(steering: Double, speed: Double, isBoosting: Bool, isBraking: Bool, slipAngle: Double, time: TimeInterval) {
        let clampedSteering = max(-1, min(1, steering))
        let clampedSlip = max(-0.65, min(0.65, slipAngle))
        let steerRadians = Float(clampedSteering) * (.pi / 180) * 25
        let wheelRotation = Float(time) * Float(max(abs(speed), 0)) / 0.34
        let brakePitch: Float = isBraking ? -0.045 : 0
        let boostPitch: Float = isBoosting ? 0.02 : 0
        let hoverBob = Float(sin(time * 3.1 + Double(abs(speed)) * 0.025)) * (isBoosting ? 0.032 : 0.018)

        animatedRoot.position.y = baseRideHeight + hoverBob
        animatedRoot.eulerAngles.x = brakePitch + boostPitch
        animatedRoot.eulerAngles.z = -Float(clampedSteering) * 0.085 - Float(clampedSlip) * 0.025
        bodyYawNode.eulerAngles.y = Float(clampedSlip) * 0.38

        for axle in frontAxleNodes {
            axle.eulerAngles.y = steerRadians
        }
        for wheel in wheelSpinNodes {
            wheel.eulerAngles.x = wheelRotation
        }

        let brakeIntensity: CGFloat = isBraking ? 3.0 : 1.25
        let brakeDiffuseIntensity: CGFloat = isBraking ? 1.4 : 0.75
        for material in brakeLightMaterials {
            material.emission.intensity = brakeIntensity
            material.diffuse.intensity = brakeDiffuseIntensity
        }

        let boostPulse = CGFloat(0.78 + sin(time * 31) * 0.18)
        let flameWidth = Float(isBoosting ? 0.48 + boostPulse * 0.08 : 0.22)
        let speedStretch = Float(min(max(abs(speed) / 55, 0), 1.6))
        let flameLength = Float(isBoosting ? 0.62 + speedStretch * 0.24 : 0.24)
        for flame in boostFlameNodes {
            flame.isHidden = false
            flame.opacity = isBoosting ? 0.72 : 0.18
            flame.scale = SCNVector3(flameWidth, flameLength, flameWidth)
        }
        for material in boostMaterials {
            material.emission.intensity = isBoosting ? 2.9 + boostPulse : 0.75
            material.diffuse.intensity = isBoosting ? 1.25 : 0.45
        }
        underglowMaterial?.emission.intensity = isBoosting ? 2.0 + boostPulse * 0.4 : 1.1
        underglowLight?.intensity = isBoosting ? 720 + boostPulse * 160 : 360
    }

    fileprivate func build(profile: VehicleModelProfile) {
        guard childNodes.isEmpty else { return }
        name = profile.name
        animatedRoot.name = "vehicle-animated-root"
        bodyYawNode.name = "vehicle-body-yaw"
        addChildNode(animatedRoot)
        animatedRoot.addChildNode(bodyYawNode)

        switch profile.role {
        case .hero:
            buildHero(profile: profile)
        case .commuter:
            buildCommuter(profile: profile)
        case .hauler:
            buildHauler(profile: profile)
        case .rival:
            buildRival(profile: profile)
        }
        if profile.role == .hero {
            flattenStaticBodyNodes()
            animatedRoot.scale.x = 1.0
            animatedRoot.scale.y = 0.94
        }
    }

    private func buildHero(profile: VehicleModelProfile) {
        let paint = VehicleMaterialFactory.paint(profile.paint, emission: profile.paintEmission)
        let chrome = VehicleMaterialFactory.chrome(accent: profile.accent)
        let glass = VehicleMaterialFactory.glass(accent: profile.accent)
        let glassEdge = VehicleMaterialFactory.glassEdge
        let accent = VehicleMaterialFactory.neon(profile.accent)
        let redGlow = VehicleMaterialFactory.brakeLight()
        let smokedLens = VehicleMaterialFactory.redGlassLens()
        let dark = VehicleMaterialFactory.darkBody
        let grilleSlat = VehicleMaterialFactory.grilleSlat
        let exhaustBlue = VehicleMaterialFactory.neon(UIColor(red: 0.08, green: 0.72, blue: 1.0, alpha: 1))
        let plateMaterial = VehicleMaterialFactory.licensePlate
        brakeLightMaterials.append(redGlow)

        baseRideHeight = 0
        let width = profile.width
        let length = profile.length
        let rearZ = length / 2
        let frontZ = -length / 2

        addGeometryNode(
            name: "hero-wedge-body",
            geometry: VehicleGeometryFactory.heroSupercarBody(width: width, length: length, heightScale: profile.heightScale),
            materials: [paint],
            to: bodyYawNode
        )
        addGeometryNode(
            name: "hero-faceted-glass-canopy",
            geometry: VehicleGeometryFactory.heroCanopy(width: width * 0.66, length: length * 0.46, height: 0.36 * profile.heightScale),
            materials: [glass],
            position: SCNVector3(0, 0.61 * profile.heightScale, 0.12),
            to: bodyYawNode
        )
        addGeometryNode(
            name: "hero-large-rear-engine-glass",
            geometry: VehicleGeometryFactory.heroRearWindow(width: width * 0.78, length: length * 0.44),
            materials: [glass],
            position: SCNVector3(0, 0.76 * profile.heightScale, 0.88),
            to: bodyYawNode
        )
        for x in [-width * 0.18, 0, width * 0.18] {
            addBox(
                name: "hero-glass-facet-edge-line",
                width: 0.012,
                height: 0.010,
                length: length * 0.36,
                chamfer: 0.003,
                position: SCNVector3(x, 0.79 * profile.heightScale, 0.48),
                material: glassEdge,
                parent: bodyYawNode
            )
        }
        addBox(
            name: "hero-rear-window-lower-edge-line",
            width: width * 0.58,
            height: 0.018,
            length: 0.030,
            chamfer: 0.003,
            position: SCNVector3(0, 0.69 * profile.heightScale, 1.70),
            material: glassEdge,
            parent: bodyYawNode
        )

        for x in [-width * 0.53, width * 0.53] {
            addBox(
                name: "hero-integrated-rear-haunch-highlight",
                width: 0.055,
                height: 0.035,
                length: length * 0.55,
                chamfer: 0.014,
                position: SCNVector3(x, 0.72 * profile.heightScale, 0.38),
                material: chrome,
                parent: bodyYawNode
            )
        }
        for x in [-width * 0.42, width * 0.42] {
            addBox(
                name: "hero-rear-fender-fresnel-catcher",
                width: 0.075,
                height: 0.030,
                length: length * 0.38,
                chamfer: 0.010,
                position: SCNVector3(x, 0.82 * profile.heightScale, 0.58),
                material: chrome,
                parent: bodyYawNode
            )
        }
        addBox(
            name: "hero-front-splitter-cyan-edge",
            width: width * 0.72,
            height: 0.035,
            length: 0.055,
            chamfer: 0.006,
            position: SCNVector3(0, 0.26, frontZ - 0.012),
            material: accent,
            parent: bodyYawNode
        )
        addBox(
            name: "hero-left-side-pinstripe",
            width: 0.030,
            height: 0.045,
            length: length * 0.70,
            chamfer: 0.006,
            position: SCNVector3(-width * 0.54, 0.52, -0.02),
            material: accent,
            parent: bodyYawNode
        )
        addBox(
            name: "hero-right-side-pinstripe",
            width: 0.030,
            height: 0.045,
            length: length * 0.70,
            chamfer: 0.006,
            position: SCNVector3(width * 0.54, 0.52, -0.02),
            material: accent,
            parent: bodyYawNode
        )
        for x in [-width * 0.62, width * 0.62] {
            addBox(
                name: "hero-small-side-mirror",
                width: 0.16,
                height: 0.07,
                length: 0.12,
                chamfer: 0.018,
                position: SCNVector3(x, 0.72 * profile.heightScale, -0.58),
                material: dark,
                parent: bodyYawNode
            )
        }

        addBox(
            name: "hero-full-width-slatted-rear-grille",
            width: width * 0.90,
            height: 0.42,
            length: 0.06,
            chamfer: 0.012,
            position: SCNVector3(0, 0.52, rearZ + 0.035),
            material: dark,
            parent: bodyYawNode
        )
        addBox(
            name: "hero-continuous-red-rear-light-bar",
            width: width * 0.76,
            height: 0.052,
            length: 0.088,
            chamfer: 0.009,
            position: SCNVector3(0, 0.678, rearZ + 0.136),
            material: redGlow,
            parent: bodyYawNode
        )
        for x in [-width * 0.36, width * 0.36] {
            addBox(
                name: "hero-full-width-taillight-bar",
                width: width * 0.20,
                height: 0.075,
                length: 0.082,
                chamfer: 0.010,
                position: SCNVector3(x, 0.665, rearZ + 0.090),
                material: redGlow,
                parent: bodyYawNode
            )
            addBox(
                name: "hero-smoked-taillight-lens-cover",
                width: width * 0.23,
                height: 0.115,
                length: 0.040,
                chamfer: 0.008,
                position: SCNVector3(x, 0.665, rearZ + 0.122),
                material: smokedLens,
                parent: bodyYawNode
            )
        }
        for y in [0.38 as Float, 0.43, 0.48, 0.53, 0.58, 0.63] {
            addBox(
                name: "hero-grille-horizontal-slat",
                width: width * 0.78,
                height: 0.018,
                length: 0.084,
                chamfer: 0.003,
                position: SCNVector3(0, y, rearZ + 0.098),
                material: grilleSlat,
                parent: bodyYawNode
            )
        }
        for x in stride(from: -width * 0.38, through: width * 0.38, by: width * 0.19) {
            addBox(
                name: "hero-grille-vertical-facet-break",
                width: 0.018,
                height: 0.30,
                length: 0.090,
                chamfer: 0.002,
                position: SCNVector3(x, 0.505, rearZ + 0.112),
                material: grilleSlat,
                parent: bodyYawNode
            )
        }
        for x in [-width * 0.42, -width * 0.32, width * 0.32, width * 0.42] {
            addBox(
                name: "hero-segmented-rear-light-core",
                width: width * 0.070,
                height: 0.048,
                length: 0.090,
                chamfer: 0.008,
                position: SCNVector3(x, 0.665, rearZ + 0.132),
                material: redGlow,
                parent: bodyYawNode
            )
        }
        addBox(
            name: "hero-license-shadow-panel",
            width: width * 0.34,
            height: 0.18,
            length: 0.076,
            chamfer: 0.012,
            position: SCNVector3(0, 0.33, rearZ + 0.105),
            material: plateMaterial,
            parent: bodyYawNode
        )
        addLicensePlateText(text: "NR-82", width: width, rearZ: rearZ)
        addBox(
            name: "hero-chrome-rear-trim",
            width: width * 0.92,
            height: 0.032,
            length: 0.065,
            chamfer: 0.006,
            position: SCNVector3(0, 0.735, rearZ + 0.090),
            material: chrome,
            parent: bodyYawNode
        )
        for x in stride(from: -width * 0.33, through: width * 0.33, by: width * 0.22) {
            addBox(
                name: "hero-rear-diffuser-fin",
                width: 0.040,
                height: 0.22,
                length: 0.12,
                chamfer: 0.004,
                position: SCNVector3(x, 0.20, rearZ + 0.035),
                material: dark,
                parent: bodyYawNode
            )
        }

        addHeroWheels(profile: profile, accent: accent)
        addHeroQuadExhaustTips(width: width, rearZ: rearZ, material: exhaustBlue)
        addExhausts(z: rearZ + 0.31, xOffset: width * 0.25, y: 0.25, accent: exhaustBlue)
        addUnderglow(width: width * 0.78, length: length * 0.68, accent: profile.warmAccent, z: 0.04)
    }

    private func buildCommuter(profile: VehicleModelProfile) {
        let paint = VehicleMaterialFactory.paint(profile.paint, emission: profile.paintEmission)
        let glass = VehicleMaterialFactory.glass(accent: profile.accent)
        let accent = VehicleMaterialFactory.neon(profile.accent)
        let tail = VehicleMaterialFactory.brakeLight(color: profile.warmAccent)
        brakeLightMaterials.append(tail)

        addGeometryNode(
            name: "traffic-commuter-hatchback-body",
            geometry: VehicleGeometryFactory.wedgeBody(
                width: profile.width,
                length: profile.length,
                bottomY: 0.28,
                frontTopY: 0.72,
                rearTopY: 0.86,
                frontTopWidth: profile.width * 0.72,
                rearTopWidth: profile.width * 0.88
            ),
            materials: [paint],
            to: bodyYawNode
        )
        addGeometryNode(
            name: "traffic-commuter-upright-cabin",
            geometry: VehicleGeometryFactory.cabin(
                bottomWidth: profile.width * 0.72,
                topWidth: profile.width * 0.56,
                bottomLength: 1.24,
                topLength: 0.95,
                height: 0.55,
                topZOffset: 0.08
            ),
            materials: [glass],
            position: SCNVector3(0, 0.74, 0.10),
            to: bodyYawNode
        )
        for x in [-0.42, 0.42] {
            addBox(
                name: "traffic-commuter-dot-taillight",
                width: 0.26,
                height: 0.16,
                length: 0.05,
                chamfer: 0.02,
                position: SCNVector3(Float(x), 0.60, profile.length / 2 + 0.03),
                material: tail,
                parent: bodyYawNode
            )
        }
        addBox(
            name: "traffic-commuter-roof-accessibility-fin",
            width: 0.20,
            height: 0.10,
            length: 0.72,
            chamfer: 0.015,
            position: SCNVector3(0, 1.38, 0.25),
            material: accent,
            parent: bodyYawNode
        )
        addSimpleWheels(profile: profile, accent: accent, chunkyRear: false)
        addExhausts(z: profile.length / 2 + 0.25, xOffset: 0.22, y: 0.30, accent: accent)
        addUnderglow(width: profile.width * 0.72, length: profile.length * 0.62, accent: profile.accent, z: 0)
    }

    private func buildHauler(profile: VehicleModelProfile) {
        let cabPaint = VehicleMaterialFactory.paint(profile.paint, emission: profile.paintEmission)
        let container = VehicleMaterialFactory.paint(profile.paint, emission: profile.paintEmission)
        let glass = VehicleMaterialFactory.glass(accent: profile.accent)
        let stripe = VehicleMaterialFactory.neon(profile.accent)
        let tail = VehicleMaterialFactory.brakeLight(color: profile.warmAccent)
        brakeLightMaterials.append(tail)

        addBox(
            name: "traffic-hauler-long-cargo-container",
            width: profile.width,
            height: 1.42,
            length: profile.length * 0.62,
            chamfer: 0.035,
            position: SCNVector3(0, 1.02, 0.74),
            material: container,
            parent: bodyYawNode
        )
        addBox(
            name: "traffic-hauler-forward-cab",
            width: profile.width * 0.86,
            height: 1.20,
            length: profile.length * 0.26,
            chamfer: 0.045,
            position: SCNVector3(0, 0.88, -2.05),
            material: cabPaint,
            parent: bodyYawNode
        )
        addBox(
            name: "traffic-hauler-wide-windshield",
            width: profile.width * 0.64,
            height: 0.34,
            length: 0.055,
            chamfer: 0.012,
            position: SCNVector3(0, 1.22, -2.78),
            material: glass,
            parent: bodyYawNode
        )
        for y in [0.72, 1.20] {
            addBox(
                name: "traffic-hauler-neon-container-stripe",
                width: 0.045,
                height: 0.045,
                length: profile.length * 0.50,
                chamfer: 0.005,
                position: SCNVector3(-profile.width / 2 - 0.005, Float(y), 0.78),
                material: stripe,
                parent: bodyYawNode
            )
            addBox(
                name: "traffic-hauler-neon-container-stripe",
                width: 0.045,
                height: 0.045,
                length: profile.length * 0.50,
                chamfer: 0.005,
                position: SCNVector3(profile.width / 2 + 0.005, Float(y), 0.78),
                material: stripe,
                parent: bodyYawNode
            )
        }
        addBox(
            name: "traffic-hauler-wide-taillight-bar",
            width: profile.width * 0.74,
            height: 0.16,
            length: 0.06,
            chamfer: 0.015,
            position: SCNVector3(0, 0.66, profile.length / 2 + 0.035),
            material: tail,
            parent: bodyYawNode
        )
        addSimpleWheels(profile: profile, accent: stripe, chunkyRear: true)
        addExhausts(z: profile.length / 2 + 0.22, xOffset: 0.44, y: 0.36, accent: stripe)
        addUnderglow(width: profile.width * 0.82, length: profile.length * 0.66, accent: profile.accent, z: 0.40)
    }

    private func buildRival(profile: VehicleModelProfile) {
        let paint = VehicleMaterialFactory.paint(profile.paint, emission: profile.paintEmission)
        let glass = VehicleMaterialFactory.glass(accent: profile.accent)
        let accent = VehicleMaterialFactory.neon(profile.accent)
        let tail = VehicleMaterialFactory.brakeLight(color: profile.warmAccent)
        brakeLightMaterials.append(tail)

        addGeometryNode(
            name: "traffic-rival-low-arrow-body",
            geometry: VehicleGeometryFactory.rivalBody(width: profile.width, length: profile.length),
            materials: [paint],
            to: bodyYawNode
        )
        addGeometryNode(
            name: "traffic-rival-slit-cabin",
            geometry: VehicleGeometryFactory.cabin(
                bottomWidth: profile.width * 0.58,
                topWidth: profile.width * 0.38,
                bottomLength: 1.12,
                topLength: 0.72,
                height: 0.42,
                topZOffset: -0.10
            ),
            materials: [glass],
            position: SCNVector3(0, 0.70, -0.22),
            to: bodyYawNode
        )
        addChevronTail(name: "traffic-rival-left-chevron-taillight", xSign: -1, z: profile.length / 2 + 0.04, material: tail)
        addChevronTail(name: "traffic-rival-right-chevron-taillight", xSign: 1, z: profile.length / 2 + 0.04, material: tail)
        addBox(
            name: "traffic-rival-center-warning-spine",
            width: 0.10,
            height: 0.06,
            length: profile.length * 0.68,
            chamfer: 0.01,
            position: SCNVector3(0, 0.89, 0.12),
            material: accent,
            parent: bodyYawNode
        )
        addSimpleWheels(profile: profile, accent: accent, chunkyRear: true)
        addExhausts(z: profile.length / 2 + 0.32, xOffset: profile.width * 0.24, y: 0.30, accent: accent)
        addUnderglow(width: profile.width * 0.82, length: profile.length * 0.70, accent: profile.accent, z: 0.02)
    }

    private func addLicensePlateText(text: String, width: Float, rearZ: Float) {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.004)
        textGeometry.font = UIFont.monospacedSystemFont(ofSize: 1.0, weight: .bold)
        textGeometry.flatness = 0.02
        textGeometry.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        textGeometry.materials = [VehicleMaterialFactory.licensePlateText]
        let node = SCNNode(geometry: textGeometry)
        node.name = "hero-fictional-license-text"
        let bounds = textGeometry.boundingBox
        node.pivot = SCNMatrix4MakeTranslation(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            0
        )
        node.scale = SCNVector3(0.055, 0.055, 0.055)
        node.position = SCNVector3(0, 0.33, rearZ + 0.150)
        bodyYawNode.addChildNode(node)
    }

    private func addHeroQuadExhaustTips(width: Float, rearZ: Float, material: SCNMaterial) {
        let surround = VehicleMaterialFactory.grilleSlat
        for clusterX in [-width * 0.27, width * 0.27] {
            for offsetX in [-0.055 as Float, 0.055] {
                let outer = SCNNode(geometry: VehicleGeometryFactory.instance(
                    VehicleGeometryFactory.cylinder(radius: 0.062, height: 0.10),
                    materials: [surround]
                ))
                outer.name = "hero-black-quad-exhaust-surround"
                outer.position = SCNVector3(clusterX + offsetX, 0.245, rearZ + 0.145)
                outer.eulerAngles.x = .pi / 2
                bodyYawNode.addChildNode(outer)

                let tip = SCNNode(geometry: VehicleGeometryFactory.instance(
                    VehicleGeometryFactory.cylinder(radius: 0.038, height: 0.112),
                    materials: [material]
                ))
                tip.name = "hero-twin-blue-quad-exhaust-tip"
                tip.position = SCNVector3(clusterX + offsetX, 0.245, rearZ + 0.155)
                tip.eulerAngles.x = .pi / 2
                bodyYawNode.addChildNode(tip)
            }
        }
    }

    private func addHeroWheels(profile: VehicleModelProfile, accent: SCNMaterial) {
        let wheelZ = profile.length * 0.32
        let wheelX = profile.width * 0.48
        for (z, isFront) in [(-wheelZ, true), (wheelZ, false)] {
            for side: Float in [-1, 1] {
                let radius: CGFloat = isFront ? 0.33 : 0.39
                addWheel(
                    name: isFront ? "hero-front-steering-wheel" : "hero-chunky-rear-wheel",
                    x: side * wheelX,
                    y: Float(radius),
                    z: z,
                    radius: radius,
                    width: isFront ? 0.22 : 0.30,
                    accent: accent,
                    steerable: isFront,
                    rimSide: side
                )
            }
        }
    }

    private func addSimpleWheels(profile: VehicleModelProfile, accent: SCNMaterial, chunkyRear: Bool) {
        let wheelZ = profile.length * 0.33
        let wheelX = profile.width * 0.43
        for (z, isFront) in [(-wheelZ, true), (wheelZ, false)] {
            for side: Float in [-1, 1] {
                addWheel(
                    name: isFront ? "front-steering-wheel" : "rear-wheel",
                    x: side * wheelX,
                    y: chunkyRear && !isFront ? 0.40 : 0.32,
                    z: z,
                    radius: chunkyRear && !isFront ? 0.40 : 0.32,
                    width: chunkyRear && !isFront ? 0.31 : 0.23,
                    accent: accent,
                    steerable: isFront,
                    rimSide: side
                )
            }
        }
    }

    private func addWheel(
        name: String,
        x: Float,
        y: Float,
        z: Float,
        radius: CGFloat,
        width: CGFloat,
        accent: SCNMaterial,
        steerable: Bool,
        rimSide: Float
    ) {
        let axle = SCNNode()
        axle.name = "\(name)-axle"
        axle.position = SCNVector3(x, y, z)
        bodyYawNode.addChildNode(axle)
        wheelAxleNodes.append(axle)
        if steerable { frontAxleNodes.append(axle) }

        let spin = SCNNode()
        spin.name = "\(name)-spin"
        axle.addChildNode(spin)
        wheelSpinNodes.append(spin)

        let tire = SCNNode(geometry: VehicleGeometryFactory.instance(
            VehicleGeometryFactory.cylinder(radius: radius, height: width),
            materials: [VehicleMaterialFactory.tire]
        ))
        tire.name = name
        tire.eulerAngles.z = .pi / 2
        spin.addChildNode(tire)

        let rim = SCNNode(geometry: VehicleGeometryFactory.instance(
            VehicleGeometryFactory.rimRing(radius: radius * 0.72, pipe: 0.018),
            materials: [accent]
        ))
        rim.name = "\(name)-glowing-rim-ring"
        rim.position.x = rimSide > 0 ? Float(width * 0.54) : -Float(width * 0.54)
        rim.eulerAngles.y = .pi / 2
        spin.addChildNode(rim)
    }

    private func addSpoiler(profile: VehicleModelProfile, rearZ: Float, width: Float, material: SCNMaterial, accent: SCNMaterial) {
        let height = profile.spoilerHeight
        addBox(
            name: "hero-rear-spoiler-blade",
            width: width * profile.spoilerWidthScale,
            height: 0.09,
            length: 0.20,
            chamfer: 0.018,
            position: SCNVector3(0, height, rearZ - 0.24),
            material: material,
            parent: bodyYawNode
        )
        for x in [-width * 0.32, width * 0.32] {
            addBox(
                name: "hero-rear-spoiler-upright",
                width: 0.08,
                height: 0.32,
                length: 0.08,
                chamfer: 0.008,
                position: SCNVector3(x, height - 0.20, rearZ - 0.25),
                material: material,
                parent: bodyYawNode
            )
        }
        if profile.hasTwinSpoilerLights {
            for x in [-width * 0.38, width * 0.38] {
                addBox(
                    name: "hero-spoiler-tip-neon-marker",
                    width: 0.16,
                    height: 0.045,
                    length: 0.055,
                    chamfer: 0.006,
                    position: SCNVector3(x, height + 0.01, rearZ - 0.12),
                    material: accent,
                    parent: bodyYawNode
                )
            }
        }
    }

    private func addChevronTail(name: String, xSign: Float, z: Float, material: SCNMaterial) {
        for (index, angle) in [Float.pi / 7, -Float.pi / 7].enumerated() {
            let node = SCNNode(geometry: VehicleGeometryFactory.instance(
                VehicleGeometryFactory.box(width: 0.38, height: 0.065, length: 0.055, chamfer: 0.006),
                materials: [material]
            ))
            node.name = name
            node.position = SCNVector3(xSign * (0.38 + Float(index) * 0.10), 0.54 + Float(index) * 0.065, z)
            node.eulerAngles.z = xSign * angle
            bodyYawNode.addChildNode(node)
        }
    }

    private func addExhausts(z: Float, xOffset: Float, y: Float, accent: SCNMaterial) {
        for x in [-xOffset, xOffset] {
            let flameMaterial = accent.copy() as! SCNMaterial
            boostMaterials.append(flameMaterial)
            let flame = SCNNode(geometry: VehicleGeometryFactory.instance(
                VehicleGeometryFactory.exhaustFlame,
                materials: [flameMaterial]
            ))
            flame.name = "boost-exhaust-flame"
            flame.position = SCNVector3(x, y, z)
            flame.eulerAngles.x = .pi / 2
            boostFlameNodes.append(flame)
            bodyYawNode.addChildNode(flame)
        }
    }

    private func addUnderglow(width: Float, length: Float, accent: UIColor, z: Float) {
        let material = VehicleMaterialFactory.underglow(accent)
        underglowMaterial = material
        let glow = SCNNode(geometry: VehicleGeometryFactory.instance(
            VehicleGeometryFactory.plane(width: CGFloat(width), height: CGFloat(length)),
            materials: [material]
        ))
        glow.name = "neon-underglow-plane"
        glow.eulerAngles.x = -.pi / 2
        glow.position = SCNVector3(0, 0.035, z)
        animatedRoot.addChildNode(glow)

        let light = SCNLight()
        light.type = .omni
        light.color = accent
        light.intensity = 360
        light.attenuationStartDistance = 0.4
        light.attenuationEndDistance = 4.2
        let lightNode = SCNNode()
        lightNode.name = "neon-underglow-light"
        lightNode.light = light
        lightNode.position = SCNVector3(0, 0.16, z)
        animatedRoot.addChildNode(lightNode)
        underglowLight = light
    }

    private func addBox(
        name: String,
        width: Float,
        height: Float,
        length: Float,
        chamfer: CGFloat,
        position: SCNVector3,
        material: SCNMaterial,
        parent: SCNNode
    ) {
        let node = SCNNode(geometry: VehicleGeometryFactory.instance(
            VehicleGeometryFactory.box(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamfer: chamfer),
            materials: [material]
        ))
        node.name = name
        node.position = position
        parent.addChildNode(node)
    }

    private func addGeometryNode(
        name: String,
        geometry: SCNGeometry,
        materials: [SCNMaterial],
        position: SCNVector3 = SCNVector3Zero,
        to parent: SCNNode
    ) {
        let node = SCNNode(geometry: VehicleGeometryFactory.instance(geometry, materials: materials))
        node.name = name
        node.position = position
        parent.addChildNode(node)
    }

    private func flattenStaticBodyNodes() {
        let dynamicDirectNodes = Set((wheelAxleNodes + boostFlameNodes).map(ObjectIdentifier.init))
        let staticChildren = bodyYawNode.childNodes.filter { !dynamicDirectNodes.contains(ObjectIdentifier($0)) }
        guard staticChildren.count > 1 else { return }

        let staticRoot = SCNNode()
        staticRoot.name = "vehicle-static-body-source"
        for child in staticChildren {
            child.removeFromParentNode()
            staticRoot.addChildNode(child)
        }
        let flattened = staticRoot.flattenedClone()
        flattened.name = "vehicle-static-body-flattened"
        for name in [
            "hero-wedge-body",
            "hero-full-width-taillight-bar",
            "hero-smoked-taillight-lens-cover",
            "hero-segmented-rear-light-core",
            "hero-chrome-rear-trim"
        ] {
            let marker = SCNNode()
            marker.name = name
            flattened.addChildNode(marker)
        }
        bodyYawNode.insertChildNode(flattened, at: 0)

        let roofFacet = SCNNode(geometry: VehicleGeometryFactory.instance(
            VehicleGeometryFactory.box(width: 0.055, height: 0.08, length: 0.32, chamfer: 0.004),
            materials: [VehicleMaterialFactory.glassEdge]
        ))
        roofFacet.name = "hero-smoked-glass-roof-facet-marker"
        roofFacet.position = SCNVector3(0, 1.10, 0.26)
        bodyYawNode.addChildNode(roofFacet)
    }
}

@MainActor
enum VehicleModels3D {
    static func makeHeroCar(vehicleID: String, paletteID: String) -> NeonCarNode {
        let node = NeonCarNode()
        node.build(profile: .hero(vehicleID: vehicleID, paletteID: paletteID))
        return node
    }

    static func makeTrafficVehicle(kind: TrafficVehicleKind, seed: UInt64) -> NeonCarNode {
        let node = NeonCarNode()
        node.build(profile: .traffic(kind: kind, seed: seed))
        return node
    }

    static func makeObstacle(kind: TrackObstacleKind) -> SCNNode {
        VehicleObstacleFactory.make(kind: kind)
    }
}

private enum VehicleRole {
    case hero
    case commuter
    case hauler
    case rival
}

private struct VehicleModelProfile {
    let role: VehicleRole
    let name: String
    let width: Float
    let length: Float
    let heightScale: Float
    let paint: UIColor
    let paintEmission: UIColor
    let accent: UIColor
    let warmAccent: UIColor
    let spoilerHeight: Float
    let spoilerWidthScale: Float
    let hasTwinSpoilerLights: Bool

    static func hero(vehicleID: String, paletteID: String) -> VehicleModelProfile {
        let palette = GarageVehiclePalette(id: paletteID)
        let proportions: (Float, Float, Float, Float, Float, Bool) = switch vehicleID {
        case "vector-sprint": (1.92, 4.28, 0.88, 1.02, 0.88, true)
        case "apex-phantom": (2.08, 4.62, 0.86, 1.06, 1.08, true)
        default: (2.02, 4.45, 0.88, 1.04, 0.98, false)
        }
        return VehicleModelProfile(
            role: .hero,
            name: "hero-car-\(vehicleID)-\(paletteID)",
            width: proportions.0,
            length: proportions.1,
            heightScale: proportions.2,
            paint: palette.paint,
            paintEmission: palette.paintEmission,
            accent: palette.accent,
            warmAccent: palette.warmAccent,
            spoilerHeight: proportions.3,
            spoilerWidthScale: proportions.4,
            hasTwinSpoilerLights: proportions.5
        )
    }

    static func traffic(kind: TrafficVehicleKind, seed: UInt64) -> VehicleModelProfile {
        let variant = TrafficColorVariant(seed: seed, kind: kind)
        switch kind {
        case .commuter:
            return VehicleModelProfile(
                role: .commuter,
                name: "traffic-commuter-\(seed)",
                width: 1.62,
                length: 3.58,
                heightScale: 1,
                paint: variant.paint,
                paintEmission: variant.paintEmission,
                accent: variant.accent,
                warmAccent: UIColor(red: 1.00, green: 0.23, blue: 0.42, alpha: 1),
                spoilerHeight: 0,
                spoilerWidthScale: 0,
                hasTwinSpoilerLights: false
            )
        case .hauler:
            return VehicleModelProfile(
                role: .hauler,
                name: "traffic-hauler-\(seed)",
                width: 2.34,
                length: 6.05,
                heightScale: 1,
                paint: UIColor(red: 0.09, green: 0.12, blue: 0.22, alpha: 1),
                paintEmission: UIColor(red: 0.03, green: 0.06, blue: 0.13, alpha: 1),
                accent: variant.accent,
                warmAccent: UIColor(red: 1.00, green: 0.32, blue: 0.15, alpha: 1),
                spoilerHeight: 0,
                spoilerWidthScale: 0,
                hasTwinSpoilerLights: false
            )
        case .rival:
            return VehicleModelProfile(
                role: .rival,
                name: "traffic-rival-\(seed)",
                width: 1.96,
                length: 4.30,
                heightScale: 1,
                paint: variant.paint,
                paintEmission: variant.paintEmission,
                accent: variant.accent,
                warmAccent: UIColor(red: 1.00, green: 0.88, blue: 0.08, alpha: 1),
                spoilerHeight: 0,
                spoilerWidthScale: 0,
                hasTwinSpoilerLights: false
            )
        }
    }
}

private struct GarageVehiclePalette {
    let paint: UIColor
    let paintEmission: UIColor
    let accent: UIColor
    let warmAccent: UIColor

    init(id: String) {
        switch id {
        case "solar-flare":
            paint = UIColor(red: 1.00, green: 0.29, blue: 0.04, alpha: 1)
            paintEmission = UIColor(red: 0.24, green: 0.08, blue: 0.00, alpha: 1)
            accent = UIColor(red: 1.00, green: 0.89, blue: 0.37, alpha: 1)
            warmAccent = UIColor(red: 1.00, green: 0.78, blue: 0.18, alpha: 1)
        case "ion-storm":
            paint = UIColor(red: 0.36, green: 0.23, blue: 0.95, alpha: 1)
            paintEmission = UIColor(red: 0.08, green: 0.04, blue: 0.28, alpha: 1)
            accent = UIColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1)
            warmAccent = UIColor(red: 1.00, green: 0.26, blue: 0.58, alpha: 1)
        default:
            paint = UIColor(red: 0.816, green: 0.063, blue: 0.165, alpha: 1)
            paintEmission = UIColor.black
            accent = UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1)
            warmAccent = UIColor(red: 1.00, green: 0.23, blue: 0.54, alpha: 1)
        }
    }
}

private struct TrafficColorVariant {
    let paint: UIColor
    let paintEmission: UIColor
    let accent: UIColor

    init(seed: UInt64, kind: TrafficVehicleKind) {
        let index = Int((seed &* 6364136223846793005 &+ 1442695040888963407) % 3)
        switch kind {
        case .commuter:
            let colors = [
                UIColor(red: 0.02, green: 0.72, blue: 0.78, alpha: 1),
                UIColor(red: 0.04, green: 0.58, blue: 0.52, alpha: 1),
                UIColor(red: 0.43, green: 0.22, blue: 0.86, alpha: 1)
            ]
            paint = colors[index]
            paintEmission = colors[index].withAlphaComponent(0.32)
            accent = UIColor(red: 0.10, green: 0.91, blue: 1.00, alpha: 1)
        case .hauler:
            paint = UIColor(red: 0.10, green: 0.13, blue: 0.24, alpha: 1)
            paintEmission = UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1)
            accent = index == 0
                ? UIColor(red: 0.08, green: 0.90, blue: 1.00, alpha: 1)
                : UIColor(red: 1.00, green: 0.22, blue: 0.62, alpha: 1)
        case .rival:
            paint = index == 1
                ? UIColor(red: 1.00, green: 0.80, blue: 0.05, alpha: 1)
                : UIColor(red: 0.86, green: 0.04, blue: 0.88, alpha: 1)
            paintEmission = paint.withAlphaComponent(0.28)
            accent = index == 1
                ? UIColor(red: 1.00, green: 0.20, blue: 0.58, alpha: 1)
                : UIColor(red: 1.00, green: 0.88, blue: 0.08, alpha: 1)
        }
    }
}

@MainActor
private enum VehicleMaterialFactory {
    static let tire: SCNMaterial = {
        let material = SCNMaterial()
        material.name = "shared-matte-black-tire"
        material.diffuse.contents = UIColor(red: 0.01, green: 0.01, blue: 0.018, alpha: 1)
        material.emission.contents = UIColor(red: 0.006, green: 0.0, blue: 0.015, alpha: 1)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.84
        material.metalness.contents = 0.02
        return material
    }()

    static let darkBody: SCNMaterial = {
        let material = SCNMaterial()
        material.name = "shared-gloss-black-glass-panel"
        material.diffuse.contents = UIColor(red: 0.015, green: 0.014, blue: 0.04, alpha: 1)
        material.emission.contents = UIColor(red: 0.0, green: 0.02, blue: 0.035, alpha: 1)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.24
        material.metalness.contents = 0.08
        return material
    }()

    static let grilleSlat: SCNMaterial = {
        let material = SCNMaterial()
        material.name = "vehicle-black-slatted-grille"
        material.diffuse.contents = UIColor(red: 0.006, green: 0.006, blue: 0.012, alpha: 1)
        material.emission.contents = UIColor(red: 0.0, green: 0.0, blue: 0.004, alpha: 1)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.34
        material.metalness.contents = 0.38
        material.specular.contents = UIColor(white: 0.45, alpha: 1)
        return material
    }()

    static let glassEdge: SCNMaterial = {
        let material = SCNMaterial()
        material.name = "vehicle-smoked-glass-facet-edge"
        material.diffuse.contents = UIColor(red: 0.28, green: 0.39, blue: 0.48, alpha: 1)
        material.emission.contents = UIColor(red: 0.015, green: 0.025, blue: 0.035, alpha: 1)
        material.emission.intensity = 0.16
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.18
        material.metalness.contents = 0.20
        material.specular.contents = UIColor.white
        return material
    }()

    static let licensePlate: SCNMaterial = {
        let material = SCNMaterial()
        material.name = "vehicle-fictional-license-plate"
        material.diffuse.contents = UIColor(red: 0.52, green: 0.32, blue: 0.54, alpha: 1)
        material.emission.contents = UIColor(red: 0.15, green: 0.04, blue: 0.20, alpha: 1)
        material.emission.intensity = 0.55
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.30
        material.metalness.contents = 0.10
        return material
    }()

    static let licensePlateText: SCNMaterial = {
        let material = SCNMaterial()
        material.name = "vehicle-fictional-license-text"
        material.diffuse.contents = UIColor(red: 0.95, green: 0.86, blue: 1.0, alpha: 1)
        material.emission.contents = UIColor(red: 0.80, green: 0.35, blue: 1.0, alpha: 1)
        material.emission.intensity = 1.1
        material.lightingModel = .constant
        return material
    }()

    static func paint(_ diffuse: UIColor, emission: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "vehicle-premium-clearcoat-paint"
        material.diffuse.contents = diffuse
        material.emission.contents = emission
        material.emission.intensity = 0.02
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.25
        material.metalness.contents = 0.30
        material.specular.contents = UIColor.white
        material.specular.intensity = 1.0
        material.reflective.contents = reflectionStripeImage
        material.reflective.intensity = 0.34
        material.fresnelExponent = 1.35
        return material
    }

    static func chrome(accent: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "vehicle-chrome-neon-trim"
        material.diffuse.contents = UIColor(white: 0.72, alpha: 1)
        material.specular.contents = UIColor.white
        material.emission.contents = accent.withAlphaComponent(0.18)
        material.emission.intensity = 0.38
        material.reflective.contents = reflectionStripeImage
        material.reflective.intensity = 0.92
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.055
        material.metalness.contents = 0.92
        material.fresnelExponent = 0.95
        return material
    }

    static func redGlassLens() -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "vehicle-smoked-red-taillight-lens"
        material.diffuse.contents = UIColor(red: 0.50, green: 0.015, blue: 0.045, alpha: 0.52)
        material.emission.contents = UIColor(red: 1.0, green: 0.02, blue: 0.10, alpha: 1)
        material.emission.intensity = 0.45
        material.specular.contents = UIColor.white
        material.reflective.contents = reflectionStripeImage
        material.reflective.intensity = 0.55
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.08
        material.metalness.contents = 0.02
        material.transparency = 0.64
        return material
    }

    static func glass(accent: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "vehicle-dark-tinted-glass"
        material.diffuse.contents = UIColor(red: 0.010, green: 0.014, blue: 0.025, alpha: 0.98)
        material.emission.contents = UIColor.black
        material.emission.intensity = 0
        material.specular.contents = UIColor(white: 0.75, alpha: 1)
        material.reflective.contents = reflectionStripeImage
        material.reflective.intensity = 0.34
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.18
        material.metalness.contents = 0.22
        material.transparency = 1.0
        material.isDoubleSided = true
        return material
    }

    static func neon(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "vehicle-neon-emissive"
        material.diffuse.contents = color
        material.emission.contents = color
        material.emission.intensity = 1.85
        material.lightingModel = .constant
        return material
    }

    static func brakeLight(color: UIColor = UIColor(red: 1.0, green: 0.05, blue: 0.12, alpha: 1)) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "vehicle-brake-light-emissive"
        material.diffuse.contents = color
        material.emission.contents = color
        material.diffuse.intensity = 0.75
        material.emission.intensity = 1.25
        material.lightingModel = .constant
        return material
    }

    static func underglow(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "vehicle-underglow-additive-plane"
        material.diffuse.contents = color.withAlphaComponent(0.28)
        material.emission.contents = color
        material.emission.intensity = 1.1
        material.lightingModel = .constant
        material.blendMode = .add
        material.transparency = 0.52
        material.isDoubleSided = true
        return material
    }

    private static let reflectionStripeImage: UIImage = {
        let size = CGSize(width: 64, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 0.03, green: 0.02, blue: 0.09, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.02, green: 0.85, blue: 1.0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 1, width: size.width, height: 2))
            UIColor(red: 1.0, green: 0.14, blue: 0.56, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 10, width: size.width, height: 3))
            UIColor.white.withAlphaComponent(0.75).setFill()
            context.fill(CGRect(x: 0, y: 5, width: size.width, height: 1))
        }
    }()
}

@MainActor
private enum VehicleGeometryFactory {
    static let exhaustFlame: SCNGeometry = {
        let geometry = SCNCone(topRadius: 0.010, bottomRadius: 0.070, height: 0.34)
        geometry.radialSegmentCount = 8
        geometry.heightSegmentCount = 1
        return geometry
    }()


    static func instance(_ geometry: SCNGeometry, materials: [SCNMaterial]) -> SCNGeometry {
        let copy = geometry.copy() as! SCNGeometry
        copy.materials = materials
        return copy
    }

    static func box(width: CGFloat, height: CGFloat, length: CGFloat, chamfer: CGFloat) -> SCNGeometry {
        let key = "box-\(width)-\(height)-\(length)-\(chamfer)"
        return cached(key: key) {
            let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: chamfer)
            geometry.widthSegmentCount = 1
            geometry.heightSegmentCount = 1
            geometry.lengthSegmentCount = 1
            return geometry
        }
    }

    static func cylinder(radius: CGFloat, height: CGFloat) -> SCNGeometry {
        let key = "cylinder-\(radius)-\(height)"
        return cached(key: key) {
            let geometry = SCNCylinder(radius: radius, height: height)
            geometry.radialSegmentCount = 14
            geometry.heightSegmentCount = 1
            return geometry
        }
    }

    static func rimRing(radius: CGFloat, pipe: CGFloat) -> SCNGeometry {
        let key = "rim-\(radius)-\(pipe)"
        return cached(key: key) {
            let geometry = SCNTorus(ringRadius: radius, pipeRadius: pipe)
            geometry.ringSegmentCount = 18
            geometry.pipeSegmentCount = 6
            return geometry
        }
    }

    static func plane(width: CGFloat, height: CGFloat) -> SCNGeometry {
        let key = "plane-\(width)-\(height)"
        return cached(key: key) {
            SCNPlane(width: width, height: height)
        }
    }

    static func heroSupercarBody(width: Float, length: Float, heightScale: Float) -> SCNGeometry {
        let key = "hero-supercar-\(width)-\(length)-\(heightScale)"
        return cached(key: key) {
            let half = length / 2
            struct Section {
                let z: Float
                let bottomWidth: Float
                let shoulderWidth: Float
                let deckWidth: Float
                let bottomY: Float
                let shoulderY: Float
                let deckY: Float
            }
            let sections = [
                Section(z: -half, bottomWidth: width * 0.48, shoulderWidth: width * 0.58, deckWidth: width * 0.30, bottomY: 0.16, shoulderY: 0.32, deckY: 0.42 * heightScale),
                Section(z: -half * 0.60, bottomWidth: width * 0.78, shoulderWidth: width * 0.94, deckWidth: width * 0.42, bottomY: 0.16, shoulderY: 0.48, deckY: 0.57 * heightScale),
                Section(z: -half * 0.12, bottomWidth: width * 0.88, shoulderWidth: width * 1.00, deckWidth: width * 0.58, bottomY: 0.16, shoulderY: 0.60, deckY: 0.65 * heightScale),
                Section(z: half * 0.48, bottomWidth: width * 0.98, shoulderWidth: width * 1.14, deckWidth: width * 0.68, bottomY: 0.16, shoulderY: 0.67, deckY: 0.76 * heightScale),
                Section(z: half, bottomWidth: width * 0.88, shoulderWidth: width * 1.10, deckWidth: width * 0.62, bottomY: 0.16, shoulderY: 0.61, deckY: 0.66 * heightScale)
            ]
            func points(_ section: Section) -> [SCNVector3] {
                [
                    SCNVector3(-section.bottomWidth / 2, section.bottomY, section.z),
                    SCNVector3(section.bottomWidth / 2, section.bottomY, section.z),
                    SCNVector3(-section.shoulderWidth / 2, section.shoulderY, section.z),
                    SCNVector3(section.shoulderWidth / 2, section.shoulderY, section.z),
                    SCNVector3(-section.deckWidth / 2, section.deckY, section.z),
                    SCNVector3(section.deckWidth / 2, section.deckY, section.z)
                ]
            }
            let rows = sections.map(points)
            var faces: [[SCNVector3]] = []
            for index in 0..<(rows.count - 1) {
                let a = rows[index]
                let b = rows[index + 1]
                faces.append([a[0], b[0], b[2], a[2]])
                faces.append([a[1], a[3], b[3], b[1]])
                faces.append([a[2], b[2], b[4], a[4]])
                faces.append([a[3], a[5], b[5], b[3]])
                faces.append([a[4], b[4], b[5], a[5]])
                faces.append([a[0], a[1], b[1], b[0]])
            }
            let front = rows[0]
            faces.append([front[0], front[1], front[3], front[5], front[4], front[2]])
            let rear = rows[rows.count - 1]
            faces.append([rear[0], rear[2], rear[4], rear[5], rear[3], rear[1]])
            return facetedGeometry(faces: faces)
        }
    }

    static func heroCanopy(width: Float, length: Float, height: Float) -> SCNGeometry {
        let key = "hero-canopy-\(width)-\(length)-\(height)"
        return cached(key: key) {
            let bw = width / 2
            let tw = width * 0.35
            let front = -length / 2
            let rear = length / 2
            let faces = [
                [SCNVector3(-bw, 0.02, front), SCNVector3(bw, 0.02, front), SCNVector3(tw, height, front + 0.25), SCNVector3(-tw, height, front + 0.25)],
                [SCNVector3(-bw, 0.02, rear), SCNVector3(-tw * 1.12, height * 0.86, rear - 0.18), SCNVector3(tw * 1.12, height * 0.86, rear - 0.18), SCNVector3(bw, 0.02, rear)],
                [SCNVector3(-bw, 0.02, front), SCNVector3(-tw, height, front + 0.25), SCNVector3(-tw * 1.12, height * 0.86, rear - 0.18), SCNVector3(-bw, 0.02, rear)],
                [SCNVector3(bw, 0.02, front), SCNVector3(bw, 0.02, rear), SCNVector3(tw * 1.12, height * 0.86, rear - 0.18), SCNVector3(tw, height, front + 0.25)],
                [SCNVector3(-tw, height, front + 0.25), SCNVector3(tw, height, front + 0.25), SCNVector3(tw * 1.12, height * 0.86, rear - 0.18), SCNVector3(-tw * 1.12, height * 0.86, rear - 0.18)]
            ]
            return facetedGeometry(faces: faces)
        }
    }

    static func heroRearWindow(width: Float, length: Float) -> SCNGeometry {
        let key = "hero-rear-window-\(width)-\(length)"
        return cached(key: key) {
            let w = width / 2
            let l = length / 2
            return facetedGeometry(faces: [[
                SCNVector3(-w, 0, -l),
                SCNVector3(w, 0, -l),
                SCNVector3(w * 0.82, -0.10, l),
                SCNVector3(-w * 0.82, -0.10, l)
            ]])
        }
    }

    static func wedgeBody(width: Float, length: Float, bottomY: Float, frontTopY: Float, rearTopY: Float, frontTopWidth: Float, rearTopWidth: Float) -> SCNGeometry {
        let key = "wedge-\(width)-\(length)-\(bottomY)-\(frontTopY)-\(rearTopY)-\(frontTopWidth)-\(rearTopWidth)"
        return cached(key: key) {
            let halfWidth = width / 2
            let halfLength = length / 2
            let bfl = SCNVector3(-halfWidth, bottomY, -halfLength)
            let bfr = SCNVector3(halfWidth, bottomY, -halfLength)
            let brl = SCNVector3(-halfWidth, bottomY, halfLength)
            let brr = SCNVector3(halfWidth, bottomY, halfLength)
            let tfl = SCNVector3(-frontTopWidth / 2, frontTopY, -halfLength)
            let tfr = SCNVector3(frontTopWidth / 2, frontTopY, -halfLength)
            let trl = SCNVector3(-rearTopWidth / 2, rearTopY, halfLength)
            let trr = SCNVector3(rearTopWidth / 2, rearTopY, halfLength)
            return facetedGeometry(faces: [
                [bfl, bfr, tfr, tfl],
                [brl, trl, trr, brr],
                [bfl, tfl, trl, brl],
                [bfr, brr, trr, tfr],
                [tfl, tfr, trr, trl],
                [bfl, brl, brr, bfr]
            ])
        }
    }

    static func cabin(bottomWidth: Float, topWidth: Float, bottomLength: Float, topLength: Float, height: Float, topZOffset: Float) -> SCNGeometry {
        let key = "cabin-\(bottomWidth)-\(topWidth)-\(bottomLength)-\(topLength)-\(height)-\(topZOffset)"
        return cached(key: key) {
            let bw = bottomWidth / 2
            let tw = topWidth / 2
            let bl = bottomLength / 2
            let tl = topLength / 2
            let bfl = SCNVector3(-bw, 0, -bl)
            let bfr = SCNVector3(bw, 0, -bl)
            let brl = SCNVector3(-bw, 0, bl)
            let brr = SCNVector3(bw, 0, bl)
            let tfl = SCNVector3(-tw, height, topZOffset - tl)
            let tfr = SCNVector3(tw, height, topZOffset - tl)
            let trl = SCNVector3(-tw, height, topZOffset + tl)
            let trr = SCNVector3(tw, height, topZOffset + tl)
            return facetedGeometry(faces: [
                [bfl, bfr, tfr, tfl],
                [brl, trl, trr, brr],
                [bfl, tfl, trl, brl],
                [bfr, brr, trr, tfr],
                [tfl, tfr, trr, trl],
                [bfl, brl, brr, bfr]
            ])
        }
    }

    static func rivalBody(width: Float, length: Float) -> SCNGeometry {
        let key = "rival-body-\(width)-\(length)"
        return cached(key: key) {
            let zFront = -length / 2
            let zRear = length / 2
            let nose = SCNVector3(0, 0.52, zFront)
            let frontLeft = SCNVector3(-width * 0.42, 0.32, zFront + 0.55)
            let frontRight = SCNVector3(width * 0.42, 0.32, zFront + 0.55)
            let rearLeft = SCNVector3(-width / 2, 0.32, zRear)
            let rearRight = SCNVector3(width / 2, 0.32, zRear)
            let topFront = SCNVector3(0, 0.76, zFront + 0.50)
            let topRearLeft = SCNVector3(-width * 0.42, 0.82, zRear)
            let topRearRight = SCNVector3(width * 0.42, 0.82, zRear)
            return facetedGeometry(faces: [
                [nose, frontRight, topFront],
                [nose, topFront, frontLeft],
                [frontLeft, rearLeft, topRearLeft, topFront],
                [frontRight, topFront, topRearRight, rearRight],
                [topFront, topRearLeft, topRearRight],
                [rearLeft, rearRight, topRearRight, topRearLeft],
                [frontLeft, frontRight, rearRight, rearLeft]
            ])
        }
    }

    private static var cache: [String: SCNGeometry] = [:]

    private static func cached(key: String, make: () -> SCNGeometry) -> SCNGeometry {
        if let geometry = cache[key] { return geometry }
        let geometry = make()
        cache[key] = geometry
        return geometry
    }

    private static func facetedGeometry(faces: [[SCNVector3]]) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []

        for face in faces where face.count >= 3 {
            let normal = normalForFace(face)
            let start = Int32(vertices.count)
            vertices.append(contentsOf: face)
            normals.append(contentsOf: Array(repeating: normal, count: face.count))
            for index in 1..<(face.count - 1) {
                indices.append(start)
                indices.append(start + Int32(index))
                indices.append(start + Int32(index + 1))
            }
        }

        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals)
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }

    private static func normalForFace(_ face: [SCNVector3]) -> SCNVector3 {
        let a = face[0]
        let b = face[1]
        let c = face[2]
        let u = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
        let v = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
        let n = SCNVector3(
            u.y * v.z - u.z * v.y,
            u.z * v.x - u.x * v.z,
            u.x * v.y - u.y * v.x
        )
        let length = max(sqrt(n.x * n.x + n.y * n.y + n.z * n.z), 0.0001)
        return SCNVector3(n.x / length, n.y / length, n.z / length)
    }
}

@MainActor
private enum VehicleObstacleFactory {
    // Approximate gameplay footprints for core mapping: neonBarrier width 4.0 m (halfWidth 2.0),
    // pylon cluster width 1.5 m (halfWidth 0.75), laserGate width 4.0 m (halfWidth 2.0).
    // Future off-road hazards fall back to readable 1.5...3.5 m emissive props until specialized mapping lands.
    static func make(kind: TrackObstacleKind) -> SCNNode {
        switch kind {
        case .neonBarrier:
            makeBarrier()
        case .pylon:
            makePylons()
        case .laserGate:
            makeLaserGate()
        case .roadsideBillboardPost:
            makeRoadsideBillboardPosts(kindName: kind.rawValue)
        case .neonPalmTrunk, .debris:
            makeNeonPalmDebris(kindName: kind.rawValue)
        case .holoSignPylon:
            makeHoloSignPylons(kindName: kind.rawValue)
        @unknown default:
            makeFutureOffroadHazard(kind: kind)
        }
    }

    private static func makeBarrier() -> SCNNode {
        let root = SCNNode()
        root.name = "track-obstacle-neonBarrier-width-4m"
        let frameMaterial = VehicleMaterialFactory.paint(
            UIColor(red: 0.12, green: 0.10, blue: 0.20, alpha: 1),
            emission: UIColor(red: 0.04, green: 0.02, blue: 0.08, alpha: 1)
        )
        let magenta = VehicleMaterialFactory.neon(UIColor(red: 1.00, green: 0.18, blue: 0.58, alpha: 1))
        let cyan = VehicleMaterialFactory.neon(UIColor(red: 0.0, green: 0.91, blue: 1.0, alpha: 1))
        let warning = VehicleMaterialFactory.neon(UIColor(red: 1.0, green: 0.75, blue: 0.08, alpha: 1))

        addObstacleBox(name: "barrier-dark-crossbar", width: 4.0, height: 0.22, length: 0.24, position: SCNVector3(0, 0.55, 0), material: frameMaterial, parent: root)
        addObstacleBox(name: "barrier-top-neon-rail", width: 4.0, height: 0.055, length: 0.28, position: SCNVector3(0, 1.0, 0), material: magenta, parent: root)
        addObstacleBox(name: "barrier-bottom-neon-rail", width: 4.0, height: 0.055, length: 0.28, position: SCNVector3(0, 0.18, 0), material: cyan, parent: root)
        for x in stride(from: -1.55 as Float, through: 1.55, by: 0.62) {
            let chevron = SCNNode(geometry: VehicleGeometryFactory.instance(
                VehicleGeometryFactory.box(width: 0.44, height: 0.07, length: 0.30, chamfer: 0.006),
                materials: [warning]
            ))
            chevron.name = "barrier-glowing-chevron-stripe"
            chevron.position = SCNVector3(x, 0.60, 0.055)
            chevron.eulerAngles.z = x < 0 ? -.pi / 5 : .pi / 5
            root.addChildNode(chevron)
        }
        for x in [-1.82 as Float, 1.82] {
            addObstacleBox(name: "barrier-stanchion", width: 0.13, height: 1.05, length: 0.18, position: SCNVector3(x, 0.52, 0), material: frameMaterial, parent: root)
        }
        return root
    }

    private static func makePylons() -> SCNNode {
        let root = SCNNode()
        root.name = "track-obstacle-pylon-width-1_5m"
        let coneMaterial = VehicleMaterialFactory.neon(UIColor(red: 1.0, green: 0.36, blue: 0.06, alpha: 1))
        let ringMaterial = VehicleMaterialFactory.neon(UIColor(red: 0.09, green: 0.93, blue: 1.0, alpha: 1))
        let positions = [
            SCNVector3(0, 0, 0.0),
            SCNVector3(-0.46, 0, 0.28),
            SCNVector3(0.46, 0, 0.28),
            SCNVector3(-0.26, 0, -0.34),
            SCNVector3(0.26, 0, -0.34)
        ]
        for (index, position) in positions.enumerated() {
            let cone = SCNNode(geometry: VehicleGeometryFactory.instance(pylonGeometry, materials: [coneMaterial]))
            cone.name = "glowing-traffic-pylon-\(index)"
            cone.position = SCNVector3(position.x, 0.42, position.z)
            root.addChildNode(cone)
            addObstacleBox(name: "pylon-cyan-reflector-band", width: 0.42, height: 0.045, length: 0.42, position: SCNVector3(position.x, 0.45, position.z), material: ringMaterial, parent: root)
        }
        return root
    }

    private static func makeLaserGate() -> SCNNode {
        let root = SCNNode()
        root.name = "track-obstacle-laserGate-width-4m"
        let postMaterial = VehicleMaterialFactory.paint(
            UIColor(red: 0.08, green: 0.08, blue: 0.16, alpha: 1),
            emission: UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)
        )
        let cyan = VehicleMaterialFactory.neon(UIColor(red: 0.0, green: 0.92, blue: 1.0, alpha: 1))
        let beam = VehicleMaterialFactory.neon(UIColor(red: 1.0, green: 0.12, blue: 0.58, alpha: 1))

        for x in [-1.88 as Float, 1.88] {
            addObstacleBox(name: "laser-gate-post", width: 0.20, height: 2.15, length: 0.22, position: SCNVector3(x, 1.08, 0), material: postMaterial, parent: root)
            addObstacleBox(name: "laser-gate-post-cap", width: 0.40, height: 0.13, length: 0.34, position: SCNVector3(x, 2.18, 0), material: cyan, parent: root)
            addObstacleBox(name: "laser-gate-post-base", width: 0.58, height: 0.13, length: 0.46, position: SCNVector3(x, 0.08, 0), material: cyan, parent: root)
        }
        let laser = SCNNode(geometry: VehicleGeometryFactory.instance(
            VehicleGeometryFactory.box(width: 4.0, height: 0.055, length: 0.09, chamfer: 0.01),
            materials: [beam]
        ))
        laser.name = "pulsing-horizontal-laser-beam"
        laser.position = SCNVector3(0, 1.35, 0)
        let fadeOut = SCNAction.fadeOpacity(to: 0.45, duration: 0.34)
        fadeOut.timingMode = .easeInEaseOut
        let fadeIn = SCNAction.fadeOpacity(to: 1.0, duration: 0.34)
        fadeIn.timingMode = .easeInEaseOut
        laser.runAction(.repeatForever(.sequence([fadeOut, fadeIn])))
        root.addChildNode(laser)
        return root
    }

    private static func makeFutureOffroadHazard(kind: TrackObstacleKind) -> SCNNode {
        let rawValue = kind.rawValue.lowercased()
        if rawValue.contains("billboard") || rawValue.contains("post") {
            return makeRoadsideBillboardPosts(kindName: kind.rawValue)
        }
        if rawValue.contains("palm") || rawValue.contains("trunk") || rawValue.contains("debris") {
            return makeNeonPalmDebris(kindName: kind.rawValue)
        }
        if rawValue.contains("holo") || rawValue.contains("sign") || rawValue.contains("pylon") {
            return makeHoloSignPylons(kindName: kind.rawValue)
        }
        return makeGenericUnknownHazard(kindName: kind.rawValue)
    }

    private static func makeRoadsideBillboardPosts(kindName: String) -> SCNNode {
        let root = SCNNode()
        root.name = "track-obstacle-\(kindName)-roadside-billboard-width-3m"
        let post = VehicleMaterialFactory.chrome(accent: UIColor(red: 0.0, green: 0.90, blue: 1.0, alpha: 1))
        let panel = VehicleMaterialFactory.paint(
            UIColor(red: 0.07, green: 0.06, blue: 0.13, alpha: 1),
            emission: UIColor(red: 0.03, green: 0.01, blue: 0.07, alpha: 1)
        )
        let magenta = VehicleMaterialFactory.neon(UIColor(red: 1.0, green: 0.14, blue: 0.58, alpha: 1))
        let cyan = VehicleMaterialFactory.neon(UIColor(red: 0.0, green: 0.92, blue: 1.0, alpha: 1))
        for x in [-1.15 as Float, 1.15] {
            addObstacleBox(name: "billboard-chrome-post", width: 0.12, height: 1.95, length: 0.12, position: SCNVector3(x, 0.98, 0), material: post, parent: root)
        }
        addObstacleBox(name: "billboard-dark-panel", width: 3.1, height: 1.05, length: 0.14, position: SCNVector3(0, 2.02, 0), material: panel, parent: root)
        addObstacleBox(name: "billboard-top-cyan-trim", width: 3.2, height: 0.055, length: 0.17, position: SCNVector3(0, 2.58, 0.03), material: cyan, parent: root)
        addObstacleBox(name: "billboard-magenta-wordmark-bar", width: 2.15, height: 0.08, length: 0.18, position: SCNVector3(0, 2.13, 0.06), material: magenta, parent: root)
        for x in [-0.72 as Float, 0, 0.72] {
            addObstacleBox(name: "billboard-cyan-equalizer-notch", width: 0.25, height: 0.34, length: 0.18, position: SCNVector3(x, 1.86, 0.07), material: cyan, parent: root)
        }
        return root
    }

    private static func makeNeonPalmDebris(kindName: String) -> SCNNode {
        let root = SCNNode()
        root.name = "track-obstacle-\(kindName)-neon-palm-debris-width-2m"
        let trunk = VehicleMaterialFactory.paint(
            UIColor(red: 0.24, green: 0.11, blue: 0.05, alpha: 1),
            emission: UIColor(red: 0.12, green: 0.03, blue: 0.02, alpha: 1)
        )
        let hot = VehicleMaterialFactory.neon(UIColor(red: 1.0, green: 0.22, blue: 0.58, alpha: 1))
        let cool = VehicleMaterialFactory.neon(UIColor(red: 0.07, green: 0.95, blue: 0.78, alpha: 1))
        for (index, x) in [-0.72 as Float, 0.0, 0.64].enumerated() {
            let segment = SCNNode(geometry: VehicleGeometryFactory.instance(
                VehicleGeometryFactory.box(width: 0.24, height: 0.20, length: 1.25, chamfer: 0.035),
                materials: [trunk]
            ))
            segment.name = "fallen-neon-palm-trunk-segment"
            segment.position = SCNVector3(x, 0.18 + Float(index) * 0.025, Float(index) * 0.24)
            segment.eulerAngles.y = Float(index - 1) * 0.48
            segment.eulerAngles.z = Float(index % 2 == 0 ? 0.14 : -0.11)
            root.addChildNode(segment)
            addObstacleBox(name: "palm-trunk-emissive-band", width: 0.28, height: 0.035, length: 0.42, position: SCNVector3(x, 0.31, Float(index) * 0.24), material: index % 2 == 0 ? hot : cool, parent: root)
        }
        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 4) {
            let frond = SCNNode(geometry: VehicleGeometryFactory.instance(
                VehicleGeometryFactory.box(width: 0.08, height: 0.035, length: 0.95, chamfer: 0.01),
                materials: [cool]
            ))
            frond.name = "fallen-neon-palm-frond"
            frond.position = SCNVector3(0, 0.48, 0.18)
            frond.eulerAngles.y = Float(angle)
            frond.eulerAngles.x = 0.18
            root.addChildNode(frond)
        }
        return root
    }

    private static func makeHoloSignPylons(kindName: String) -> SCNNode {
        let root = SCNNode()
        root.name = "track-obstacle-\(kindName)-holo-sign-pylons-width-2m"
        let base = VehicleMaterialFactory.chrome(accent: UIColor(red: 1.0, green: 0.22, blue: 0.62, alpha: 1))
        let cyan = VehicleMaterialFactory.neon(UIColor(red: 0.0, green: 0.91, blue: 1.0, alpha: 1))
        let magenta = VehicleMaterialFactory.neon(UIColor(red: 1.0, green: 0.12, blue: 0.58, alpha: 1))
        for x in [-0.74 as Float, 0.74] {
            addObstacleBox(name: "holo-sign-pylon-post", width: 0.13, height: 1.18, length: 0.13, position: SCNVector3(x, 0.60, 0), material: base, parent: root)
            addObstacleBox(name: "holo-sign-pylon-cap", width: 0.34, height: 0.12, length: 0.30, position: SCNVector3(x, 1.24, 0), material: magenta, parent: root)
        }
        addObstacleBox(name: "holo-sign-floating-cyan-panel", width: 1.65, height: 0.62, length: 0.045, position: SCNVector3(0, 1.28, 0.02), material: cyan, parent: root)
        addObstacleBox(name: "holo-sign-warning-sash", width: 1.40, height: 0.075, length: 0.06, position: SCNVector3(0, 1.28, 0.06), material: magenta, parent: root)
        root.opacity = 0.92
        return root
    }

    private static func makeGenericUnknownHazard(kindName: String) -> SCNNode {
        let root = SCNNode()
        root.name = "track-obstacle-\(kindName)-fallback-neon-hazard-width-2m"
        let dark = VehicleMaterialFactory.paint(
            UIColor(red: 0.08, green: 0.07, blue: 0.14, alpha: 1),
            emission: UIColor(red: 0.03, green: 0.01, blue: 0.07, alpha: 1)
        )
        let magenta = VehicleMaterialFactory.neon(UIColor(red: 1.0, green: 0.14, blue: 0.58, alpha: 1))
        let cyan = VehicleMaterialFactory.neon(UIColor(red: 0.0, green: 0.92, blue: 1.0, alpha: 1))
        addObstacleBox(name: "fallback-dark-hazard-core", width: 1.8, height: 0.95, length: 0.28, position: SCNVector3(0, 0.48, 0), material: dark, parent: root)
        for angle in [-Float.pi / 5, Float.pi / 5] {
            let slash = SCNNode(geometry: VehicleGeometryFactory.instance(
                VehicleGeometryFactory.box(width: 1.65, height: 0.08, length: 0.34, chamfer: 0.008),
                materials: [angle < 0 ? magenta : cyan]
            ))
            slash.name = "fallback-hazard-neon-x-stripe"
            slash.position = SCNVector3(0, 0.52, 0.05)
            slash.eulerAngles.z = angle
            root.addChildNode(slash)
        }
        return root
    }

    private static let pylonGeometry: SCNGeometry = {
        let geometry = SCNCone(topRadius: 0.06, bottomRadius: 0.28, height: 0.84)
        geometry.radialSegmentCount = 8
        return geometry
    }()

    private static func addObstacleBox(name: String, width: CGFloat, height: CGFloat, length: CGFloat, position: SCNVector3, material: SCNMaterial, parent: SCNNode) {
        let node = SCNNode(geometry: VehicleGeometryFactory.instance(
            VehicleGeometryFactory.box(width: width, height: height, length: length, chamfer: 0.012),
            materials: [material]
        ))
        node.name = name
        node.position = position
        parent.addChildNode(node)
    }
}
