import SpriteKit

final class RaceScene: SKScene {
    private var simulation = RaceSimulation()
    private var previousUpdateTime: TimeInterval?
    private let carNode = SKShapeNode()
    private let speedLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let roadNode = SKNode()

    override convenience init() {
        self.init(size: CGSize(width: 1920, height: 1080))
    }

    override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.015, green: 0.005, blue: 0.06, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func didMove(to view: SKView) {
        guard children.isEmpty else {
            return
        }

        view.preferredFramesPerSecond = 120
        buildHorizon()
        buildRoadGrid()
        buildCar()
        buildHUD()
    }

    override func update(_ currentTime: TimeInterval) {
        let frameDelta = previousUpdateTime.map { currentTime - $0 } ?? 0
        previousUpdateTime = currentTime

        let steering = sin(currentTime * 0.75) * 0.45
        simulation.advance(
            frameDelta: frameDelta,
            command: PlayerCommand(
                steering: steering,
                throttle: 1,
                brake: 0,
                isBoosting: false
            )
        )

        render(snapshot: simulation.renderSnapshot, currentTime: currentTime)
    }

    private func buildHorizon() {
        let sun = SKShapeNode(circleOfRadius: 175)
        sun.fillColor = SKColor(red: 1, green: 0.18, blue: 0.48, alpha: 1)
        sun.strokeColor = SKColor(red: 1, green: 0.74, blue: 0.18, alpha: 1)
        sun.lineWidth = 8
        sun.glowWidth = 28
        sun.position = CGPoint(x: 0, y: 180)
        sun.zPosition = -20
        addChild(sun)

        let skyline = SKShapeNode(path: skylinePath())
        skyline.fillColor = SKColor(red: 0.03, green: 0.01, blue: 0.11, alpha: 1)
        skyline.strokeColor = SKColor(red: 0.88, green: 0.08, blue: 1, alpha: 1)
        skyline.lineWidth = 5
        skyline.glowWidth = 10
        skyline.zPosition = -10
        addChild(skyline)
    }

    private func buildRoadGrid() {
        roadNode.zPosition = 0
        addChild(roadNode)

        let road = CGMutablePath()
        road.move(to: CGPoint(x: -80, y: 40))
        road.addLine(to: CGPoint(x: -900, y: -540))
        road.move(to: CGPoint(x: 80, y: 40))
        road.addLine(to: CGPoint(x: 900, y: -540))

        for lane in -4...4 {
            let horizonX = CGFloat(lane) * 18
            let foregroundX = CGFloat(lane) * 180
            road.move(to: CGPoint(x: horizonX, y: 40))
            road.addLine(to: CGPoint(x: foregroundX, y: -540))
        }

        for index in 0..<14 {
            let progress = CGFloat(index) / 13
            let eased = progress * progress
            let y = 40 - eased * 580
            let halfWidth = 80 + eased * 820
            road.move(to: CGPoint(x: -halfWidth, y: y))
            road.addLine(to: CGPoint(x: halfWidth, y: y))
        }

        let grid = SKShapeNode(path: road)
        grid.strokeColor = SKColor(red: 0, green: 0.95, blue: 1, alpha: 0.9)
        grid.lineWidth = 3
        grid.glowWidth = 8
        roadNode.addChild(grid)
    }

    private func buildCar() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -170, y: -80))
        path.addLine(to: CGPoint(x: -125, y: 70))
        path.addLine(to: CGPoint(x: -70, y: 125))
        path.addLine(to: CGPoint(x: 70, y: 125))
        path.addLine(to: CGPoint(x: 125, y: 70))
        path.addLine(to: CGPoint(x: 170, y: -80))
        path.closeSubpath()

        carNode.path = path
        carNode.fillColor = SKColor(red: 0.96, green: 0.02, blue: 0.38, alpha: 1)
        carNode.strokeColor = SKColor(red: 0, green: 1, blue: 0.95, alpha: 1)
        carNode.lineWidth = 8
        carNode.glowWidth = 18
        carNode.position = CGPoint(x: 0, y: -330)
        carNode.zPosition = 20
        addChild(carNode)
    }

    private func buildHUD() {
        speedLabel.fontSize = 38
        speedLabel.fontColor = SKColor(red: 0, green: 1, blue: 0.95, alpha: 1)
        speedLabel.horizontalAlignmentMode = .right
        speedLabel.verticalAlignmentMode = .top
        speedLabel.position = CGPoint(x: 890, y: 490)
        speedLabel.zPosition = 100
        addChild(speedLabel)
    }

    private func render(snapshot: RaceRenderSnapshot, currentTime: TimeInterval) {
        let alpha = CGFloat(snapshot.interpolationAlpha)
        let interpolatedLateral = CGFloat(snapshot.previous.lateralPosition) * (1 - alpha)
            + CGFloat(snapshot.current.lateralPosition) * alpha
        let interpolatedDistance = snapshot.previous.distance * (1 - Double(alpha))
            + snapshot.current.distance * Double(alpha)
        let state = snapshot.current

        carNode.position.x = interpolatedLateral * 420
        carNode.zRotation = -interpolatedLateral * 0.08
        roadNode.position.y = CGFloat(interpolatedDistance.truncatingRemainder(dividingBy: 35))
        speedLabel.text = "SPEED \(Int(state.speed * 2.4))"

        let pulse = 0.88 + sin(currentTime * 4) * 0.05
        carNode.setScale(pulse)
    }

    private func skylinePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -960, y: -20))

        var x: CGFloat = -960
        let widths: [CGFloat] = [120, 80, 145, 95, 170, 75, 110, 135, 90, 160, 105, 130]
        let heights: [CGFloat] = [150, 230, 120, 280, 190, 320, 175, 250, 135, 300, 205, 160]

        for index in widths.indices {
            let width = widths[index]
            let height = heights[index]
            path.addLine(to: CGPoint(x: x, y: height))
            x += width
            path.addLine(to: CGPoint(x: x, y: height))
        }

        path.addLine(to: CGPoint(x: 960, y: -20))
        path.closeSubpath()
        return path
    }
}

