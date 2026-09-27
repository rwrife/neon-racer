import SpriteKit

enum VehicleClass: String, CaseIterable, Sendable {
    case playerWedge
    case trafficCoupe
    case trafficHauler
    case rivalInterceptor

    var assetName: String {
        switch self {
        case .playerWedge: "player-wedge"
        case .trafficCoupe: "traffic-coupe"
        case .trafficHauler: "traffic-hauler"
        case .rivalInterceptor: "rival-interceptor"
        }
    }
}

enum VehiclePaletteVariant: String, CaseIterable, Sendable {
    case electricDusk
    case hardSignal
    case blueOrange

    init(settings: AccessibilitySettings) {
        if settings.highContrast {
            self = .hardSignal
        } else {
            self = settings.palette == .blueOrange ? .blueOrange : .electricDusk
        }
    }
}

enum VehicleMotionState: String, CaseIterable, Sendable {
    case idle
    case steerLeft
    case steerRight
    case driftLeft
    case driftRight
    case brake
    case boost
    case damage
}

struct VehicleFrame: Equatable, Sendable {
    let vehicleClass: VehicleClass
    let state: VehicleMotionState
    let phase: Int

    init(
        vehicleClass: VehicleClass = .playerWedge,
        state: VehicleMotionState,
        phase: Int
    ) {
        self.vehicleClass = vehicleClass
        self.state = state
        self.phase = phase
    }

    var atlasName: String {
        "vehicle.\(vehicleClass.assetName).\(state.rawValue).\(String(format: "%02d", phase))"
    }
}

struct VehicleVisualInput: Equatable, Sendable {
    var steering: Double
    var drift: Double
    var brake: Double
    var boost: Bool
    var damage: Double
}

struct VehicleFrameSelector: Sendable {
    private(set) var current = VehicleFrame(state: .idle, phase: 0)
    private var animationClock: TimeInterval = 0

    mutating func select(input: VehicleVisualInput, deltaTime: TimeInterval) -> VehicleFrame {
        animationClock += max(0, deltaTime)
        let state: VehicleMotionState
        if input.damage > 0.01 {
            state = .damage
        } else if input.boost {
            state = .boost
        } else if input.brake > 0.15 {
            state = .brake
        } else if input.drift > 0.42 {
            state = input.steering < 0 ? .driftLeft : .driftRight
        } else {
            let enterThreshold = 0.22
            let exitThreshold = 0.14
            switch current.state {
            case .steerLeft where input.steering < -exitThreshold:
                state = .steerLeft
            case .steerRight where input.steering > exitThreshold:
                state = .steerRight
            default:
                if input.steering < -enterThreshold {
                    state = .steerLeft
                } else if input.steering > enterThreshold {
                    state = .steerRight
                } else {
                    state = .idle
                }
            }
        }

        if state != current.state {
            animationClock = 0
        }
        let phaseCount = state == .boost || state == .damage ? 2 : 1
        current = VehicleFrame(
            state: state,
            phase: Int(animationClock / 0.08) % phaseCount
        )
        return current
    }
}

struct VehicleArtDefinition: Sendable {
    struct Point: Sendable {
        let x: CGFloat
        let y: CGFloat
    }

    let vehicleClass: VehicleClass
    let canvasSize: CGSize
    let anchor: CGPoint
    let collisionBounds: CGRect
    let body: [Point]
    let cabin: [Point]
    let signature: [Point]

    var atlasPrefix: String {
        "vehicle.\(vehicleClass.assetName)"
    }
}

enum VehicleArtCatalog {
    static let nativeCanvasSize = CGSize(width: 384, height: 256)
    static let atlasName = "vehicles@3x"
    static let definitions: [VehicleArtDefinition] = [
        VehicleArtDefinition(
            vehicleClass: .playerWedge,
            canvasSize: nativeCanvasSize,
            anchor: CGPoint(x: 0.5, y: 0.18),
            collisionBounds: CGRect(x: 0.10, y: 0.12, width: 0.80, height: 0.62),
            body: points([
                (0.04, 0.16), (0.13, 0.63), (0.29, 0.82), (0.71, 0.82),
                (0.87, 0.63), (0.96, 0.16), (0.76, 0.08), (0.24, 0.08)
            ]),
            cabin: points([(0.27, 0.58), (0.36, 0.76), (0.64, 0.76), (0.73, 0.58)]),
            signature: points([(0.16, 0.32), (0.34, 0.25), (0.50, 0.29), (0.66, 0.25), (0.84, 0.32)])
        ),
        VehicleArtDefinition(
            vehicleClass: .trafficCoupe,
            canvasSize: nativeCanvasSize,
            anchor: CGPoint(x: 0.5, y: 0.16),
            collisionBounds: CGRect(x: 0.18, y: 0.10, width: 0.64, height: 0.70),
            body: points([
                (0.18, 0.14), (0.22, 0.60), (0.35, 0.84), (0.65, 0.84),
                (0.78, 0.60), (0.82, 0.14), (0.68, 0.08), (0.32, 0.08)
            ]),
            cabin: points([(0.32, 0.57), (0.39, 0.78), (0.61, 0.78), (0.68, 0.57)]),
            signature: points([(0.28, 0.28), (0.42, 0.28), (0.58, 0.28), (0.72, 0.28)])
        ),
        VehicleArtDefinition(
            vehicleClass: .trafficHauler,
            canvasSize: nativeCanvasSize,
            anchor: CGPoint(x: 0.5, y: 0.14),
            collisionBounds: CGRect(x: 0.14, y: 0.08, width: 0.72, height: 0.82),
            body: points([
                (0.13, 0.12), (0.14, 0.78), (0.25, 0.91), (0.75, 0.91),
                (0.86, 0.78), (0.87, 0.12), (0.73, 0.07), (0.27, 0.07)
            ]),
            cabin: points([(0.24, 0.61), (0.29, 0.82), (0.71, 0.82), (0.76, 0.61)]),
            signature: points([(0.20, 0.26), (0.36, 0.26), (0.36, 0.38), (0.64, 0.38), (0.64, 0.26), (0.80, 0.26)])
        ),
        VehicleArtDefinition(
            vehicleClass: .rivalInterceptor,
            canvasSize: nativeCanvasSize,
            anchor: CGPoint(x: 0.5, y: 0.18),
            collisionBounds: CGRect(x: 0.08, y: 0.11, width: 0.84, height: 0.66),
            body: points([
                (0.03, 0.14), (0.20, 0.28), (0.16, 0.61), (0.34, 0.86),
                (0.66, 0.86), (0.84, 0.61), (0.80, 0.28), (0.97, 0.14),
                (0.72, 0.08), (0.28, 0.08)
            ]),
            cabin: points([(0.29, 0.57), (0.38, 0.78), (0.62, 0.78), (0.71, 0.57)]),
            signature: points([(0.15, 0.32), (0.36, 0.32), (0.50, 0.20), (0.64, 0.32), (0.85, 0.32)])
        )
    ]

    static let player = definitions[0]

    static func definition(for vehicleClass: VehicleClass) -> VehicleArtDefinition {
        definitions.first { $0.vehicleClass == vehicleClass } ?? player
    }

    private static func points(_ values: [(CGFloat, CGFloat)]) -> [VehicleArtDefinition.Point] {
        values.map(VehicleArtDefinition.Point.init)
    }
}

final class VehicleArtNode: SKNode {
    private let definition: VehicleArtDefinition
    private let shadowNode = SKShapeNode()
    private let bodyNode = SKShapeNode()
    private let cabinNode = SKShapeNode()
    private let signatureNode = SKShapeNode()
    private let leftExhaust = SKShapeNode()
    private let rightExhaust = SKShapeNode()
    private let frameNameLabel = SKLabelNode(fontNamed: "Menlo")
    private var paletteVariant = VehiclePaletteVariant.electricDusk

    init(definition: VehicleArtDefinition) {
        self.definition = definition
        super.init()
        name = definition.atlasPrefix
        build()
        apply(palette: .electricDusk, reducedEffects: false)
        apply(
            frame: VehicleFrame(vehicleClass: definition.vehicleClass, state: .idle, phase: 0),
            reducedMotion: false
        )
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(palette: VehiclePaletteVariant, reducedEffects: Bool) {
        paletteVariant = palette
        let colors = VehicleColors(variant: palette)
        shadowNode.fillColor = colors.shadow
        bodyNode.fillColor = colors.body
        bodyNode.strokeColor = colors.edge
        cabinNode.fillColor = colors.cabin
        cabinNode.strokeColor = colors.edge
        signatureNode.strokeColor = colors.emissive
        leftExhaust.fillColor = colors.warning
        rightExhaust.fillColor = colors.warning
        bodyNode.glowWidth = reducedEffects ? 1 : 8
        cabinNode.glowWidth = reducedEffects ? 0 : 3
        signatureNode.glowWidth = reducedEffects ? 1 : 10
    }

    func apply(frame: VehicleFrame, reducedMotion: Bool) {
        name = frame.atlasName
        frameNameLabel.text = frame.atlasName
        frameNameLabel.isHidden = true

        let direction: CGFloat
        switch frame.state {
        case .steerLeft, .driftLeft: direction = -1
        case .steerRight, .driftRight: direction = 1
        default: direction = 0
        }
        let isDrifting = frame.state == .driftLeft || frame.state == .driftRight
        bodyNode.zRotation = reducedMotion ? 0 : direction * (isDrifting ? 0.075 : 0.035)
        cabinNode.position.x = reducedMotion ? 0 : direction * (isDrifting ? 12 : 5)
        signatureNode.position.x = cabinNode.position.x * 0.4

        let isBoosting = frame.state == .boost
        let exhaustScale: CGFloat = isBoosting ? (frame.phase == 0 ? 1.65 : 2.05) : 0.55
        leftExhaust.yScale = reducedMotion ? (isBoosting ? 1.7 : 0.55) : exhaustScale
        rightExhaust.yScale = leftExhaust.yScale
        leftExhaust.alpha = isBoosting ? 1 : 0.45
        rightExhaust.alpha = leftExhaust.alpha

        let colors = VehicleColors(variant: paletteVariant)
        if frame.state == .brake {
            signatureNode.strokeColor = colors.warning
            signatureNode.lineWidth = 12
        } else if frame.state == .damage {
            signatureNode.strokeColor = frame.phase == 0 ? .white : colors.warning
            signatureNode.lineWidth = 9
        } else {
            signatureNode.strokeColor = colors.emissive
            signatureNode.lineWidth = 7
        }
        alpha = frame.state == .damage && frame.phase == 0 ? 0.72 : 1
    }

    func setDebugGuidesVisible(_ visible: Bool) {
        childNode(withName: "anchor-guide")?.isHidden = !visible
        childNode(withName: "collision-guide")?.isHidden = !visible
        frameNameLabel.isHidden = !visible
    }

    private func build() {
        let width = definition.canvasSize.width
        let height = definition.canvasSize.height
        shadowNode.path = CGPath(
            ellipseIn: CGRect(x: -width * 0.46, y: -height * 0.10, width: width * 0.92, height: height * 0.25),
            transform: nil
        )
        shadowNode.zPosition = -3
        addChild(shadowNode)

        bodyNode.path = path(definition.body)
        bodyNode.lineWidth = 7
        addChild(bodyNode)

        cabinNode.path = path(definition.cabin)
        cabinNode.lineWidth = 5
        cabinNode.zPosition = 1
        addChild(cabinNode)

        signatureNode.path = openPath(definition.signature)
        signatureNode.lineWidth = 7
        signatureNode.lineCap = .round
        signatureNode.zPosition = 2
        addChild(signatureNode)

        configureExhaust(leftExhaust, x: -width * 0.23)
        configureExhaust(rightExhaust, x: width * 0.23)

        let anchorGuide = SKShapeNode(circleOfRadius: 7)
        anchorGuide.name = "anchor-guide"
        anchorGuide.fillColor = .yellow
        anchorGuide.strokeColor = .black
        anchorGuide.zPosition = 10
        anchorGuide.isHidden = true
        addChild(anchorGuide)

        let bounds = definition.collisionBounds
        let collisionRect = CGRect(
            x: (bounds.minX - definition.anchor.x) * width,
            y: (bounds.minY - definition.anchor.y) * height,
            width: bounds.width * width,
            height: bounds.height * height
        )
        let collisionGuide = SKShapeNode(rect: collisionRect)
        collisionGuide.name = "collision-guide"
        collisionGuide.strokeColor = .yellow
        collisionGuide.lineWidth = 3
        collisionGuide.zPosition = 9
        collisionGuide.isHidden = true
        addChild(collisionGuide)

        frameNameLabel.fontSize = 12
        frameNameLabel.fontColor = .white
        frameNameLabel.verticalAlignmentMode = .top
        frameNameLabel.position = CGPoint(x: 0, y: -height * 0.18)
        frameNameLabel.zPosition = 10
        addChild(frameNameLabel)
    }

    private func configureExhaust(_ node: SKShapeNode, x: CGFloat) {
        let flame = CGMutablePath()
        flame.move(to: CGPoint(x: -10, y: 0))
        flame.addLine(to: CGPoint(x: 0, y: -42))
        flame.addLine(to: CGPoint(x: 10, y: 0))
        flame.closeSubpath()
        node.path = flame
        node.position = CGPoint(x: x, y: -definition.canvasSize.height * 0.10)
        node.zPosition = -1
        addChild(node)
    }

    private func path(_ points: [VehicleArtDefinition.Point]) -> CGPath {
        let result = openPath(points)
        result.closeSubpath()
        return result
    }

    private func openPath(_ points: [VehicleArtDefinition.Point]) -> CGMutablePath {
        let result = CGMutablePath()
        guard let first = points.first else { return result }
        result.move(to: projected(first))
        for point in points.dropFirst() {
            result.addLine(to: projected(point))
        }
        return result
    }

    private func projected(_ point: VehicleArtDefinition.Point) -> CGPoint {
        CGPoint(
            x: (point.x - definition.anchor.x) * definition.canvasSize.width,
            y: (point.y - definition.anchor.y) * definition.canvasSize.height
        )
    }
}

private struct VehicleColors {
    let body: SKColor
    let cabin: SKColor
    let edge: SKColor
    let emissive: SKColor
    let warning: SKColor
    let shadow: SKColor

    init(variant: VehiclePaletteVariant) {
        switch variant {
        case .electricDusk:
            body = SKColor(red: 0.78, green: 0.05, blue: 0.43, alpha: 1)
            cabin = SKColor(red: 0.08, green: 0.05, blue: 0.17, alpha: 1)
            edge = SKColor(red: 0, green: 0.90, blue: 0.96, alpha: 1)
            emissive = SKColor(red: 1, green: 0.78, blue: 0.34, alpha: 1)
            warning = SKColor(red: 1, green: 0.23, blue: 0.42, alpha: 1)
        case .hardSignal:
            body = SKColor(red: 0.86, green: 0.07, blue: 0.52, alpha: 1)
            cabin = SKColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
            edge = .white
            emissive = SKColor(red: 0, green: 1, blue: 1, alpha: 1)
            warning = SKColor(red: 1, green: 0.84, blue: 0, alpha: 1)
        case .blueOrange:
            body = SKColor(red: 0.08, green: 0.36, blue: 0.62, alpha: 1)
            cabin = SKColor(red: 0.04, green: 0.12, blue: 0.18, alpha: 1)
            edge = SKColor(red: 0.26, green: 0.70, blue: 1, alpha: 1)
            emissive = SKColor(red: 1, green: 0.62, blue: 0.11, alpha: 1)
            warning = SKColor(red: 0.96, green: 0.90, blue: 0.32, alpha: 1)
        }
        shadow = SKColor(white: 0, alpha: 0.48)
    }
}
