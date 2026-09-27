import SpriteKit

#if DEBUG
final class VehicleArtPreviewScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.02, green: 0.015, blue: 0.06, alpha: 1)
        buildSheet()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        buildSheet()
    }

    private func buildSheet() {
        guard children.isEmpty else { return }
        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "ORIGINAL PROCEDURAL VEHICLE SHEET"
        title.fontSize = 34
        title.position = CGPoint(x: 0, y: 475)
        addChild(title)

        let classes = VehicleClass.allCases
        let palettes = VehiclePaletteVariant.allCases
        for (row, vehicleClass) in classes.enumerated() {
            for (column, palette) in palettes.enumerated() {
                let node = VehicleArtNode(definition: VehicleArtCatalog.definition(for: vehicleClass))
                node.setScale(0.54)
                node.position = CGPoint(
                    x: CGFloat(column - 1) * 520,
                    y: 300 - CGFloat(row) * 220
                )
                node.apply(palette: palette, reducedEffects: false)
                node.setDebugGuidesVisible(true)
                addChild(node)

                let label = SKLabelNode(fontNamed: "Menlo-Bold")
                label.text = "\(vehicleClass.rawValue) / \(palette.rawValue)"
                label.fontSize = 18
                label.position = CGPoint(x: node.position.x, y: node.position.y + 95)
                addChild(label)
            }
        }

        let states = VehicleMotionState.allCases
        for (index, state) in states.enumerated() {
            let node = VehicleArtNode(definition: VehicleArtCatalog.player)
            node.setScale(0.24)
            node.position = CGPoint(x: -735 + CGFloat(index) * 210, y: -485)
            node.apply(
                frame: VehicleFrame(state: state, phase: state == .boost ? 1 : 0),
                reducedMotion: false
            )
            addChild(node)

            let label = SKLabelNode(fontNamed: "Menlo")
            label.text = state.rawValue
            label.fontSize = 14
            label.position = CGPoint(x: node.position.x, y: -535)
            addChild(label)
        }
    }
}
#endif
