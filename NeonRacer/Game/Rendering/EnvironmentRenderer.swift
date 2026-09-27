import CoreGraphics
import SpriteKit

enum EnvironmentDepthLayer: String, CaseIterable {
    case sky
    case far
    case mid
    case near
    case roadside
    case foreground
}

struct EnvironmentLayerConfiguration {
    let depth: EnvironmentDepthLayer
    let parallax: CGFloat
    let baseZPosition: CGFloat
    let density: Int
    let tileWidth: CGFloat
}

struct EnvironmentPalette: Equatable {
    let skyTop: SKColor
    let skyBottom: SKColor
    let silhouetteFar: SKColor
    let silhouetteMid: SKColor
    let silhouetteNear: SKColor
    let primary: SKColor
    let secondary: SKColor
    let celestial: SKColor
    let fog: SKColor

    static func accessibility(_ palette: PaletteComponents) -> Self {
        Self(
            skyTop: palette.background.spriteColor.mixed(with: .black, amount: 0.35),
            skyBottom: palette.panel.spriteColor.mixed(with: palette.secondary.spriteColor, amount: 0.18),
            silhouetteFar: palette.panel.spriteColor.mixed(with: palette.primary.spriteColor, amount: 0.12),
            silhouetteMid: palette.panel.spriteColor.mixed(with: palette.secondary.spriteColor, amount: 0.16),
            silhouetteNear: palette.background.spriteColor.mixed(with: palette.primary.spriteColor, amount: 0.08),
            primary: palette.primary.spriteColor,
            secondary: palette.secondary.spriteColor,
            celestial: palette.warning.spriteColor,
            fog: palette.primary.spriteColor
        )
    }
}

struct EnvironmentConfiguration {
    let layers: [EnvironmentLayerConfiguration]
    let roadsideSpacing: Double
    let roadsideVisibleDistance: Double
    let palette: EnvironmentPalette

    static func demo(palette: EnvironmentPalette) -> Self {
        Self(
            layers: [
                .init(depth: .sky, parallax: 0.01, baseZPosition: -100, density: 48, tileWidth: 1_920),
                .init(depth: .far, parallax: 0.025, baseZPosition: -80, density: 3, tileWidth: 1_920),
                .init(depth: .mid, parallax: 0.06, baseZPosition: -60, density: 3, tileWidth: 1_920),
                .init(depth: .near, parallax: 0.12, baseZPosition: -40, density: 3, tileWidth: 1_920),
                .init(depth: .roadside, parallax: 1, baseZPosition: 6, density: 32, tileWidth: 0),
                .init(depth: .foreground, parallax: 0.24, baseZPosition: 12, density: 3, tileWidth: 1_920)
            ],
            roadsideSpacing: 42,
            roadsideVisibleDistance: 900,
            palette: palette
        )
    }
}

/// Adapter for the current road projection. A future road renderer can populate curve and
/// elevation without changing environment ownership or pooling.
struct EnvironmentProjection {
    let distance: Double
    let lateralOffset: CGFloat
    let horizonY: CGFloat
    let foregroundY: CGFloat
    let horizonHalfWidth: CGFloat
    let foregroundHalfWidth: CGFloat
    let curveOffset: CGFloat
    let elevationOffset: CGFloat
    let visibleDistance: Double

    func project(side: CGFloat, distanceAhead: Double) -> (position: CGPoint, scale: CGFloat, visible: Bool) {
        let normalized = CGFloat(1 - distanceAhead / visibleDistance).clamped(to: 0...1)
        let perspective = normalized * normalized
        let y = horizonY + (foregroundY - horizonY) * perspective + elevationOffset * perspective
        let halfWidth = horizonHalfWidth + (foregroundHalfWidth - horizonHalfWidth) * perspective
        let cameraOffset = -lateralOffset * halfWidth * 0.55
        let bend = curveOffset * perspective * perspective
        return (
            CGPoint(x: side * (halfWidth + 38 + 54 * perspective) + cameraOffset + bend, y: y),
            0.18 + perspective * 1.15,
            distanceAhead >= 0 && distanceAhead <= visibleDistance
        )
    }
}

struct EnvironmentDiagnostics {
    let visibleNodeCount: Int
    let estimatedDrawCount: Int
    let layerDrawCounts: [EnvironmentDepthLayer: Int]

    static let empty = Self(visibleNodeCount: 0, estimatedDrawCount: 0, layerDrawCounts: [:])
}

@MainActor
final class EnvironmentRenderer {
    let rootNode = SKNode()

    private let quality: CosmeticQualityConfiguration
    private var configuration: EnvironmentConfiguration
    private var layerNodes: [EnvironmentDepthLayer: SKNode] = [:]
    private var tiledNodes: [EnvironmentDepthLayer: [SKNode]] = [:]
    private var starNodes: [SKShapeNode] = []
    private var roadsideProps: [RoadsideProp] = []
    private var fogNodes: [SKShapeNode] = []
    private var colorNodes: [EnvironmentDepthLayer: [SKShapeNode]] = [:]
    private let skyA = SKSpriteNode()
    private let skyB = SKSpriteNode()
    private var skyFrontIsA = true
    private var paletteFrom: EnvironmentPalette
    private var paletteTo: EnvironmentPalette
    private var paletteProgress: CGFloat = 1
    private var paletteDuration: TimeInterval = 0

    init(size: CGSize, quality: CosmeticQualityConfiguration, configuration: EnvironmentConfiguration) {
        self.quality = quality
        self.configuration = configuration
        paletteFrom = configuration.palette
        paletteTo = configuration.palette
        build(size: size)
    }

    func transition(to palette: EnvironmentPalette, duration: TimeInterval) {
        paletteFrom = displayedPalette
        paletteTo = palette
        paletteDuration = duration
        if duration > 0 {
            paletteProgress = 0
            prepareSkyTransition(size: skyA.size)
        } else {
            paletteProgress = 1
            let texture = Self.gradientTexture(top: palette.skyTop, bottom: palette.skyBottom)
            skyA.texture = texture
            skyB.texture = texture
            skyA.alpha = 1
            skyB.alpha = 0
            skyFrontIsA = true
            paletteFrom = palette
            applyPalette(palette)
        }
    }

    func update(
        projection: EnvironmentProjection,
        deltaTime: TimeInterval,
        currentTime: TimeInterval,
        reduceMotion: Bool
    ) -> EnvironmentDiagnostics {
        updatePalette(deltaTime: deltaTime)
        updateTiledLayers(projection: projection, reduceMotion: reduceMotion)
        updateStars(projection: projection, currentTime: currentTime, reduceMotion: reduceMotion)
        updateRoadside(projection: projection)
        updateFog(currentTime: currentTime, reduceMotion: reduceMotion)
        return diagnostics()
    }

    private var displayedPalette: EnvironmentPalette {
        EnvironmentPalette.lerp(from: paletteFrom, to: paletteTo, progress: paletteProgress)
    }

    private func build(size: CGSize) {
        rootNode.name = "environment"
        for layer in configuration.layers {
            let node = SKNode()
            node.name = "environment-\(layer.depth.rawValue)"
            node.zPosition = layer.baseZPosition
            rootNode.addChild(node)
            layerNodes[layer.depth] = node
        }
        buildSky(size: size)
        buildTiledLayer(.far, pathFactory: mountainPath, fill: configuration.palette.silhouetteFar)
        buildTiledLayer(.mid, pathFactory: skylinePath, fill: configuration.palette.silhouetteMid)
        buildTiledLayer(.near, pathFactory: nearRidgePath, fill: configuration.palette.silhouetteNear)
        buildHorizonGridAndFog()
        buildForeground()
        buildRoadside()
        applyPalette(configuration.palette)
    }

    private func buildSky(size: CGSize) {
        guard let layer = layerNodes[.sky],
              let config = configuration.layers.first(where: { $0.depth == .sky }) else { return }
        for sky in [skyA, skyB] {
            sky.size = size
            sky.position = CGPoint(x: 0, y: 0)
            sky.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.addChild(sky)
        }
        skyA.texture = Self.gradientTexture(
            top: configuration.palette.skyTop,
            bottom: configuration.palette.skyBottom
        )
        skyA.alpha = 1
        skyB.alpha = 0

        let starCount = max(8, Int(Double(config.density) * quality.sceneryDensityScale))
        for index in 0..<starCount {
            let radius = CGFloat(1 + index % 3)
            let star = SKShapeNode(circleOfRadius: radius)
            let x = CGFloat((index * 347) % 1_900) - 950
            let y = CGFloat((index * 193) % 500) + 30
            star.position = CGPoint(x: x, y: y)
            star.alpha = 0.28 + CGFloat(index % 5) * 0.11
            star.lineWidth = 0
            layer.addChild(star)
            starNodes.append(star)
        }

        let sun = SKShapeNode(circleOfRadius: 142)
        sun.name = "celestial"
        sun.position = CGPoint(x: 315, y: 205)
        sun.lineWidth = 6
        sun.glowWidth = 18 * CGFloat(quality.glowScale)
        layer.addChild(sun)
        colorNodes[.sky, default: []].append(sun)
    }

    private func buildTiledLayer(
        _ depth: EnvironmentDepthLayer,
        pathFactory: () -> CGPath,
        fill: SKColor
    ) {
        guard let layer = layerNodes[depth],
              let config = configuration.layers.first(where: { $0.depth == depth }) else { return }
        var tiles: [SKNode] = []
        for tileIndex in -1...1 {
            let shape = SKShapeNode(path: pathFactory())
            shape.fillColor = fill
            shape.strokeColor = depth == .mid ? configuration.palette.secondary : configuration.palette.primary
            shape.lineWidth = depth == .mid ? 3 : 2
            shape.glowWidth = CGFloat(depth == .mid ? 5 : 2) * CGFloat(quality.glowScale)
            shape.position.x = CGFloat(tileIndex) * config.tileWidth
            layer.addChild(shape)
            tiles.append(shape)
            colorNodes[depth, default: []].append(shape)
        }
        tiledNodes[depth] = tiles
    }

    private func buildForeground() {
        guard let layer = layerNodes[.foreground] else { return }
        for side: CGFloat in [-1, 1] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: side * 960, y: -540))
            path.addLine(to: CGPoint(x: side * 960, y: 20))
            path.addLine(to: CGPoint(x: side * 805, y: -80))
            path.addLine(to: CGPoint(x: side * 700, y: -250))
            path.addLine(to: CGPoint(x: side * 590, y: -540))
            path.closeSubpath()
            let shape = SKShapeNode(path: path)
            shape.lineWidth = 4
            layer.addChild(shape)
            colorNodes[.foreground, default: []].append(shape)
        }
    }

    private func buildHorizonGridAndFog() {
        guard let layer = layerNodes[.near] else { return }
        let gridPath = CGMutablePath()
        for line in -8...8 {
            gridPath.move(to: CGPoint(x: CGFloat(line) * 58, y: 35))
            gridPath.addLine(to: CGPoint(x: CGFloat(line) * 145, y: -230))
        }
        for index in 0..<7 {
            let progress = CGFloat(index) / 6
            let y = 35 - progress * progress * 265
            gridPath.move(to: CGPoint(x: -960, y: y))
            gridPath.addLine(to: CGPoint(x: 960, y: y))
        }
        let grid = SKShapeNode(path: gridPath)
        grid.name = "environment-grid"
        grid.lineWidth = 1.5
        grid.alpha = 0.24
        layer.addChild(grid)
        colorNodes[.near, default: []].append(grid)

        for index in 0..<2 {
            let fog = SKShapeNode(rectOf: CGSize(width: 2_150, height: 42 + CGFloat(index) * 18))
            fog.name = "fog-band"
            fog.position.y = CGFloat(5 - index * 70)
            fog.alpha = 0.08 + CGFloat(index) * 0.035
            fog.lineWidth = 0
            layer.addChild(fog)
            fogNodes.append(fog)
        }
    }

    private func buildRoadside() {
        guard let layer = layerNodes[.roadside],
              let config = configuration.layers.first(where: { $0.depth == .roadside }) else { return }
        let count = max(6, Int(Double(config.density) * quality.sceneryDensityScale))
        for index in 0..<count {
            let node = SKShapeNode(path: Self.roadsidePropPath(kind: index % 3))
            node.lineWidth = 3
            node.glowWidth = 3 * CGFloat(quality.glowScale)
            layer.addChild(node)
            roadsideProps.append(
                RoadsideProp(node: node, side: index.isMultiple(of: 2) ? -1 : 1, slot: index / 2)
            )
            colorNodes[.roadside, default: []].append(node)
        }
    }

    private func updateTiledLayers(projection: EnvironmentProjection, reduceMotion: Bool) {
        for config in configuration.layers where config.tileWidth > 0 {
            guard let tiles = tiledNodes[config.depth] else { continue }
            let movement = reduceMotion ? 0 : CGFloat(projection.distance) * config.parallax
            let lateral = reduceMotion ? 0 : projection.lateralOffset * 120 * config.parallax
            let wrapped = movement.truncatingRemainder(dividingBy: config.tileWidth)
            for (index, tile) in tiles.enumerated() {
                tile.position.x = (CGFloat(index - 1) * config.tileWidth) - wrapped - lateral
            }
        }
    }

    private func updateStars(
        projection: EnvironmentProjection,
        currentTime: TimeInterval,
        reduceMotion: Bool
    ) {
        let drift = reduceMotion ? 0 : CGFloat(projection.distance).truncatingRemainder(dividingBy: 1_920) * 0.005
        for (index, star) in starNodes.enumerated() {
            let baseX = CGFloat((index * 347) % 1_900) - 950
            star.position.x = Self.wrap(baseX - drift - projection.lateralOffset * 3, width: 1_920)
            if quality.expensiveEffectsEnabled && !reduceMotion {
                star.alpha = 0.42 + 0.2 * sin(currentTime * 0.7 + Double(index))
            }
        }
    }

    private func updateRoadside(projection: EnvironmentProjection) {
        let pairCount = max(1, roadsideProps.count / 2)
        for prop in roadsideProps {
            let cycle = configuration.roadsideVisibleDistance + configuration.roadsideSpacing
            let slotDistance = Double(prop.slot) / Double(pairCount) * cycle
            let distanceAhead = (
                slotDistance - projection.distance.truncatingRemainder(dividingBy: cycle) + cycle
            ).truncatingRemainder(dividingBy: cycle)
            let projected = projection.project(side: prop.side, distanceAhead: distanceAhead)
            prop.node.isHidden = !projected.visible
            prop.node.position = projected.position
            prop.node.setScale(projected.scale)
            prop.node.zPosition = projected.scale
            prop.node.alpha = min(1, 0.25 + projected.scale)
        }
    }

    private func updateFog(currentTime: TimeInterval, reduceMotion: Bool) {
        guard !fogNodes.isEmpty else { return }
        for (index, fog) in fogNodes.enumerated() {
            fog.position.x = reduceMotion ? 0 : sin(currentTime * 0.08 + Double(index)) * 90
        }
    }

    private func updatePalette(deltaTime: TimeInterval) {
        guard paletteProgress < 1 else { return }
        if paletteDuration <= 0 {
            paletteProgress = 1
        } else {
            paletteProgress = min(1, paletteProgress + CGFloat(deltaTime / paletteDuration))
        }
        let palette = displayedPalette
        applyPalette(palette)
        let front = skyFrontIsA ? skyA : skyB
        let back = skyFrontIsA ? skyB : skyA
        front.alpha = 1 - paletteProgress
        back.alpha = paletteProgress
        if paletteProgress == 1 {
            front.alpha = 0
            back.alpha = 1
            skyFrontIsA.toggle()
            paletteFrom = paletteTo
        }
    }

    private func prepareSkyTransition(size: CGSize) {
        let target = skyFrontIsA ? skyB : skyA
        target.size = size
        target.texture = Self.gradientTexture(top: paletteTo.skyTop, bottom: paletteTo.skyBottom)
        target.alpha = paletteProgress
    }

    private func applyPalette(_ palette: EnvironmentPalette) {
        for star in starNodes {
            star.fillColor = palette.primary
        }
        for node in colorNodes[.sky] ?? [] {
            node.fillColor = palette.celestial
            node.strokeColor = palette.secondary
        }
        apply(palette.silhouetteFar, stroke: palette.primary, to: .far)
        apply(palette.silhouetteMid, stroke: palette.secondary, to: .mid)
        apply(palette.silhouetteNear, stroke: palette.primary, to: .near)
        apply(palette.silhouetteNear, stroke: palette.secondary, to: .foreground)
        for (index, node) in (colorNodes[.roadside] ?? []).enumerated() {
            node.fillColor = palette.silhouetteNear
            node.strokeColor = index.isMultiple(of: 3) ? palette.secondary : palette.primary
        }
        for fog in fogNodes {
            fog.fillColor = palette.fog
        }
    }

    private func apply(_ fill: SKColor, stroke: SKColor, to depth: EnvironmentDepthLayer) {
        for node in colorNodes[depth] ?? [] {
            node.fillColor = fill
            node.strokeColor = stroke
        }
    }

    private func diagnostics() -> EnvironmentDiagnostics {
        var counts: [EnvironmentDepthLayer: Int] = [:]
        var visibleNodes = 0
        for (depth, layer) in layerNodes {
            let count = layer.children.reduce(0) { $0 + ($1.isHidden || $1.alpha <= 0 ? 0 : 1) }
            counts[depth] = count
            visibleNodes += count
        }
        return EnvironmentDiagnostics(
            visibleNodeCount: visibleNodes,
            estimatedDrawCount: counts.values.reduce(0, +),
            layerDrawCounts: counts
        )
    }

    private func mountainPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -960, y: -80))
        let points: [CGPoint] = [
            .init(x: -960, y: 35), .init(x: -790, y: 190), .init(x: -650, y: 65),
            .init(x: -430, y: 260), .init(x: -210, y: 80), .init(x: 30, y: 220),
            .init(x: 245, y: 55), .init(x: 510, y: 245), .init(x: 720, y: 70),
            .init(x: 960, y: 175), .init(x: 960, y: -80)
        ]
        points.forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private func skylinePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -960, y: -105))
        var x: CGFloat = -960
        let widths: [CGFloat] = [95, 130, 70, 155, 110, 85, 145, 75, 125, 100, 150, 90, 130]
        let heights: [CGFloat] = [80, 145, 205, 115, 255, 160, 105, 230, 130, 185, 95, 215, 125]
        let count = max(3, Int(Double(widths.count) * quality.sceneryDensityScale))
        for index in widths.indices.prefix(count) {
            path.addLine(to: CGPoint(x: x, y: heights[index] - 70))
            x += widths[index]
            path.addLine(to: CGPoint(x: x, y: heights[index] - 70))
        }
        path.addLine(to: CGPoint(x: 960, y: -105))
        path.closeSubpath()
        return path
    }

    private func nearRidgePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -960, y: -230))
        let points: [CGPoint] = [
            .init(x: -960, y: -75), .init(x: -760, y: 30), .init(x: -500, y: -85),
            .init(x: -250, y: 60), .init(x: 5, y: -65), .init(x: 280, y: 45),
            .init(x: 535, y: -90), .init(x: 755, y: 25), .init(x: 960, y: -55),
            .init(x: 960, y: -230)
        ]
        points.forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private static func roadsidePropPath(kind: Int) -> CGPath {
        let path = CGMutablePath()
        switch kind {
        case 0:
            path.move(to: CGPoint(x: -12, y: 0))
            path.addLine(to: CGPoint(x: -8, y: 65))
            path.addLine(to: CGPoint(x: 8, y: 65))
            path.addLine(to: CGPoint(x: 12, y: 0))
            path.closeSubpath()
            path.move(to: CGPoint(x: -25, y: 65))
            path.addLine(to: CGPoint(x: 25, y: 65))
        case 1:
            path.move(to: CGPoint(x: -28, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 72))
            path.addLine(to: CGPoint(x: 28, y: 0))
            path.closeSubpath()
        default:
            path.move(to: CGPoint(x: -7, y: 0))
            path.addLine(to: CGPoint(x: -7, y: 90))
            path.addLine(to: CGPoint(x: 7, y: 90))
            path.addLine(to: CGPoint(x: 7, y: 0))
            path.closeSubpath()
            path.move(to: CGPoint(x: -22, y: 78))
            path.addLine(to: CGPoint(x: 22, y: 78))
        }
        return path
    }

    private static func gradientTexture(top: SKColor, bottom: SKColor) -> SKTexture? {
        let height = 128
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [bottom.cgColor, top.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return nil }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: height),
            options: []
        )
        guard let image = context.makeImage() else { return nil }
        return SKTexture(cgImage: image)
    }

    private static func wrap(_ value: CGFloat, width: CGFloat) -> CGFloat {
        var wrapped = (value + width / 2).truncatingRemainder(dividingBy: width)
        if wrapped < 0 { wrapped += width }
        return wrapped - width / 2
    }
}

private final class RoadsideProp {
    let node: SKShapeNode
    let side: CGFloat
    let slot: Int

    init(node: SKShapeNode, side: CGFloat, slot: Int) {
        self.node = node
        self.side = side
        self.slot = slot
    }
}

private extension EnvironmentPalette {
    static func lerp(from: Self, to: Self, progress: CGFloat) -> Self {
        Self(
            skyTop: from.skyTop.mixed(with: to.skyTop, amount: progress),
            skyBottom: from.skyBottom.mixed(with: to.skyBottom, amount: progress),
            silhouetteFar: from.silhouetteFar.mixed(with: to.silhouetteFar, amount: progress),
            silhouetteMid: from.silhouetteMid.mixed(with: to.silhouetteMid, amount: progress),
            silhouetteNear: from.silhouetteNear.mixed(with: to.silhouetteNear, amount: progress),
            primary: from.primary.mixed(with: to.primary, amount: progress),
            secondary: from.secondary.mixed(with: to.secondary, amount: progress),
            celestial: from.celestial.mixed(with: to.celestial, amount: progress),
            fog: from.fog.mixed(with: to.fog, amount: progress)
        )
    }
}

private extension SKColor {
    func mixed(with other: SKColor, amount: CGFloat) -> SKColor {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let first = cgColor.converted(
            to: colorSpace,
            intent: .defaultIntent,
            options: nil
        )?.components,
        let second = other.cgColor.converted(
            to: colorSpace,
            intent: .defaultIntent,
            options: nil
        )?.components,
        first.count >= 4,
        second.count >= 4 else { return other }
        let t = amount.clamped(to: 0...1)
        return SKColor(
            red: first[0] + (second[0] - first[0]) * t,
            green: first[1] + (second[1] - first[1]) * t,
            blue: first[2] + (second[2] - first[2]) * t,
            alpha: first[3] + (second[3] - first[3]) * t
        )
    }
}

extension RGBColor {
    var spriteColor: SKColor {
        SKColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: 1
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
