import CoreGraphics
import SceneKit
import UIKit

@MainActor
final class NeonEnvironment3D {
    let rootNode = SCNNode()

    private struct ThemeAssets {
        let sky: UIImage
        let horizonGlow: UIImage
        let mountain: UIImage
        let sunDisc: SCNMaterial
        let sunHalo: SCNMaterial
    }

    private struct BillboardTextureKey: Hashable {
        let title: String
        let subtitle: String
        let style: HoloBillboardStyle3D
        let borderColor: UIColor
    }

    private static let groundGradient = groundGradientImage()
    private var themeAssets: [String: ThemeAssets] = [:]
    private var billboardTextures: [BillboardTextureKey: UIImage] = [:]

    private let quality: CosmeticQualityTier
    private var renderSceneryScale: Double
    private weak var scene: SCNScene?
    private var currentTheme: EnvironmentTheme3D
    private var reduceMotion = false
    private var highContrast = false
    private var reduceFlashing = false
    private var lastUpdateTime: TimeInterval = 0

    private let warmHorizonGlowNode = SCNNode()
    private let sunNode = SCNNode()
    private let sunDiscNode = SCNNode()
    private let sunHaloNode = SCNNode()
    private let starNode = SCNNode()
    private let groundNode = SCNNode()
    private let gridNode = SCNNode()
    private let magentaGridNode = SCNNode()
    private let coastNode = SCNNode()
    private let cityNode = SCNNode()
    private let peaksNode = SCNNode()
    private let centralSkylineNode = SCNNode()
    private let facetedMountainNode = SCNNode()
    private let horizonLineNode = SCNNode()
    private let horizonNodes = SCNNode()
    private let auroraNode = SCNNode()
    private let hazeNode = SCNNode()
    private let eyeCandyRoot = SCNNode()
    private let blimpNode = SCNNode()
    private let maglevNode = SCNNode()
    private let lightningNode = SCNNode()

    private var ambientLightNode: SCNNode?
    private var directionalLightNode: SCNNode?
    private var gridMaterials: [SCNMaterial] = []
    private var magentaGridMaterials: [SCNMaterial] = []
    private var starMaterials: [SCNMaterial] = []
    private var skylineMaterials: [SCNMaterial] = []
    private var centralSkylineFillMaterials: [SCNMaterial] = []
    private var centralSkylineRimMaterials: [SCNMaterial] = []
    private var facetedMountainFillMaterials: [SCNMaterial] = []
    private var facetedMountainEdgeMaterials: [SCNMaterial] = []
    private var horizonLineMaterials: [SCNMaterial] = []
    private var groundMaterials: [SCNMaterial] = []
    private var warmHorizonGlowMaterials: [SCNMaterial] = []
    private var mountainLineMaterials: [SCNMaterial] = []
    private var oceanMaterials: [SCNMaterial] = []
    private var auroraMaterials: [SCNMaterial] = []
    private var hazeMaterials: [SCNMaterial] = []
    private var lightningMaterials: [SCNMaterial] = []
    private var hoverActors: [EyeCandyActor3D] = []
    private var meteorActors: [EyeCandyActor3D] = []
    private var searchlightActors: [EyeCandyActor3D] = []
    private var fireworkActors: [EyeCandyActor3D] = []
    private var coastCandyActors: [EyeCandyActor3D] = []
    private var satelliteActors: [EyeCandyActor3D] = []
    private var hologramActors: [EyeCandyActor3D] = []
    private var blimpAdNodes: [SCNNode] = []
    private var maglevCars: [SCNNode] = []
    private var horizonForward = SCNVector3(0, 0, -1)
    private let gridCellSize: Float

    init(quality: CosmeticQualityTier) {
        self.quality = quality
        self.renderSceneryScale = RenderQualityConfiguration.preset(for: RenderQualityTier(cosmeticTier: quality)).sceneryDensityScale
        self.currentTheme = .sunsetCoast
        self.gridCellSize = quality == .efficiency ? 48 : 36
        rootNode.name = "neon-environment-root"
        horizonNodes.name = "neon-environment-horizon-layers"
        rootNode.addChildNode(horizonNodes)
        build()
        for theme in [EnvironmentTheme3D.sunsetCoast, .neonCity, .midnightPeaks] {
            _ = assets(for: theme)
        }
        horizonNodes.enumerateHierarchy { child, _ in child.renderingOrder -= 3_000 }
        applyTheme(.sunsetCoast, animated: false)
    }

    func attach(to scene: SCNScene) {
        self.scene = scene
        if rootNode.parent == nil {
            scene.rootNode.addChildNode(rootNode)
        }
        configureScene(scene, theme: currentTheme)
        installLights(on: scene)
    }

    func setEnvironment(_ environmentID: String, animated: Bool) {
        let theme = EnvironmentTheme3D.theme(for: environmentID)
        guard theme.id != currentTheme.id else { return }
        let shouldAnimate = animated && !reduceMotion
        currentTheme = theme
        applyTheme(theme, animated: shouldAnimate)
    }

    func themeID(for environmentID: String) -> String {
        EnvironmentTheme3D.theme(for: environmentID).id
    }

    /// Road surface height near the player; the ground grid stays just below it so it never covers the road.
    var groundLevel: Float?

    func update(cameraNode: SCNNode, time: TimeInterval, speedRatio: Double) {
        update(
            cameraPosition: cameraNode.presentation.worldPosition,
            cameraForward: cameraNode.presentation.forwardVectorFlattened,
            time: time,
            speedRatio: speedRatio
        )
    }

    /// Preferred per-frame entry point: takes the camera pose directly instead of querying SceneKit.
    func update(cameraPosition: SCNVector3, cameraForward rawForward: SCNVector3, time: TimeInterval, speedRatio: Double) {
        lastUpdateTime = time
        let cameraForward = SCNVector3(rawForward.x, 0, rawForward.z).nrNormalized(default: SCNVector3(0, 0, -1))
        horizonForward = horizonForward.nrLerped(to: cameraForward, t: reduceMotion ? 0.08 : 0.025).nrNormalized(default: cameraForward)

        updateGrid(cameraPosition: cameraPosition, speedRatio: speedRatio)
        updateHorizon(cameraPosition: cameraPosition)
        updateSun(cameraPosition: cameraPosition, time: time, speedRatio: speedRatio)
        updateStars(cameraPosition: cameraPosition, time: time)
        updateMotionEffects(time: time, speedRatio: speedRatio)
        updateEyeCandy(time: time, speedRatio: speedRatio)
    }

    func apply(reduceMotion: Bool, highContrast: Bool, reduceFlashing: Bool = false) {
        self.reduceMotion = reduceMotion
        self.highContrast = highContrast
        self.reduceFlashing = reduceFlashing
        applyTheme(currentTheme, animated: false)
    }

    func apply(renderQualityTier: RenderQualityTier) {
        renderSceneryScale = RenderQualityConfiguration.preset(for: renderQualityTier).sceneryDensityScale
        applyTheme(currentTheme, animated: false)
    }

    /// Factory for future track-mapped roadside streaming. The core 3D race scene can place
    /// returned nodes along `TrackWorldMapper3D` frames and use `roadsidePropKinds` plus
    /// `roadsidePropSpacingHint` to choose a theme-appropriate pool without duplicating art.
    func makeRoadsideProp(kind: String, seed: UInt64) -> SCNNode {
        let normalized = kind.lowercased().replacingOccurrences(of: "_", with: "-")
        switch normalized {
        case "palm", "palm-tree", "neon-palm", "coast-palm":
            return makePalm(seed: seed)
        case "sign", "signpost", "neon-signpost", "billboard", "neon-billboard", "holo-billboard":
            return makeSign(seed: seed)
        case "tower", "retro-tower", "futurist-tower", "neon-tower":
            return makeRetroTower(seed: seed)
        case "light", "light-pole", "streetlight", "neon-light-pole":
            return makeLightPole(seed: seed)
        case "relay", "relay-beacon", "beacon", "mountain-relay":
            return makeRelayBeacon(seed: seed)
        case "tunnel", "tunnel-ring", "arch", "city-arch":
            return makeTunnelRing(seed: seed)
        default:
            return makeSign(seed: seed)
        }
    }

    func roadsidePropKinds(for environmentID: String) -> [String] {
        switch EnvironmentTheme3D.theme(for: environmentID).id {
        case "neon-city":
            ["neon-signpost", "holo-billboard", "retro-tower", "light-pole", "tunnel-ring", "billboard"]
        case "midnight-peaks":
            ["relay-beacon", "retro-tower", "light-pole", "neon-signpost"]
        default:
            ["neon-palm", "holo-billboard", "retro-tower", "light-pole"]
        }
    }

    func roadsidePropSpacingHint(for environmentID: String) -> Double {
        switch EnvironmentTheme3D.theme(for: environmentID).id {
        case "neon-city": 42
        case "midnight-peaks": 115
        default: 78
        }
    }

    private var renderSceneryOpacityScale: CGFloat {
        CGFloat(min(max(renderSceneryScale, 0.45), 1))
    }

    private func build() {
        buildSkyObjects()
        buildGrid()
        buildDistantLayers()
        buildAtmosphere()
        buildEyeCandy()
    }

    private func configureScene(_ scene: SCNScene, theme: EnvironmentTheme3D) {
        scene.background.contents = assets(for: theme).sky
        scene.fogStartDistance = highContrast ? 420 : max(320, theme.fogStart)
        scene.fogEndDistance = highContrast ? 1_150 : max(980, theme.fogEnd)
        scene.fogDensityExponent = 2
        let baseFog = UIColor(red: 0.055, green: 0.020, blue: 0.130, alpha: 1)
        scene.fogColor = highContrast ? baseFog.darker(amount: 0.20) : baseFog
    }

    private func installLights(on scene: SCNScene) {
        if ambientLightNode == nil {
            let ambient = SCNNode()
            ambient.name = "neon-environment-ambient-light"
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            scene.rootNode.addChildNode(ambient)
            ambientLightNode = ambient
        }
        if directionalLightNode == nil {
            let directional = SCNNode()
            directional.name = "neon-environment-directional-light"
            directional.light = SCNLight()
            directional.light?.type = .directional
            directional.eulerAngles = SCNVector3(-0.86, 0.32, 0)
            scene.rootNode.addChildNode(directional)
            directionalLightNode = directional
        }
        ambientLightNode?.light?.color = currentTheme.ambientLight
        directionalLightNode?.light?.color = currentTheme.directionalLight
        directionalLightNode?.light?.intensity = highContrast ? 820 : 650
    }

    private func buildSkyObjects() {
        warmHorizonGlowNode.name = "soft-magenta-orange-horizon-glow-band"
        let glowMaterial = Self.constantMaterial(.white, emission: Self.horizonBandGlowImage(color: .magenta), transparency: 0.82)
        glowMaterial.diffuse.contents = Self.horizonBandGlowImage(color: .magenta)
        glowMaterial.transparent.contents = glowMaterial.diffuse.contents
        glowMaterial.writesToDepthBuffer = false
        warmHorizonGlowMaterials.append(glowMaterial)
        warmHorizonGlowNode.geometry = SCNPlane(width: 1_260, height: 250)
        warmHorizonGlowNode.geometry?.materials = [glowMaterial]
        warmHorizonGlowNode.position = SCNVector3(0, -5, -86)
        warmHorizonGlowNode.renderingOrder = -40
        horizonNodes.addChildNode(warmHorizonGlowNode)

        sunNode.name = "striped-synthwave-horizon-sun"
        sunNode.renderingOrder = -20
        sunHaloNode.geometry = SCNPlane(width: 500, height: 500)
        sunDiscNode.geometry = SCNPlane(width: 295, height: 295)
        sunHaloNode.position.z = -0.8
        sunDiscNode.position.z = 0
        sunNode.addChildNode(sunHaloNode)
        sunNode.addChildNode(sunDiscNode)
        horizonNodes.addChildNode(sunNode)

        starNode.name = "neon-starfield"
        let starCount = switch quality {
        case .efficiency: 42
        case .balanced: 82
        case .fidelity: 140
        }
        for index in 0..<starCount {
            let size = CGFloat(0.9 + Double((index * 17) % 4) * 0.38)
            let material = Self.constantMaterial(.white, emission: UIColor(white: 1, alpha: 1), transparency: 0.72)
            let star = SCNNode(geometry: SCNPlane(width: size, height: size))
            star.geometry?.materials = [material]
            star.position = SCNVector3(
                Float(((index * 997) % 1_520) - 760),
                Float(132 + ((index * 577) % 270)),
                Float(-15 - ((index * 61) % 30))
            )
            starNode.addChildNode(star)
            starMaterials.append(material)
        }
        horizonNodes.addChildNode(starNode)
    }

    private func buildGrid() {
        groundNode.name = "opaque-deep-violet-grid-ground"
        gridNode.name = "legacy-flat-cyan-grid-disabled"
        magentaGridNode.name = "legacy-flat-magenta-grid-disabled"
        // Track-mapped low-poly terrain now owns the ground plane and neon edge grid.
        // Keep these nodes for theme/update compatibility, but do not attach flat geometry.
    }

    /// Merges many static child nodes into one draw call per material.
    private static func flattenChildren(of node: SCNNode) {
        let container = SCNNode()
        node.childNodes.forEach { container.addChildNode($0.removeFromParentNodeReturningSelf()) }
        let flat = container.flattenedClone()
        flat.name = (node.name ?? "grid") + "-flattened"
        node.addChildNode(flat)
    }

    private func buildDistantLayers() {
        coastNode.name = "sunset-coast-distant-layer"
        cityNode.name = "neon-city-distant-layer"
        peaksNode.name = "midnight-peaks-distant-layer"
        centralSkylineNode.name = "centered-dark-polygon-skyline"
        facetedMountainNode.name = "low-violet-faceted-mountains"
        horizonLineNode.name = "glowing-cyan-horizon-line"
        horizonNodes.addChildNode(facetedMountainNode)
        horizonNodes.addChildNode(coastNode)
        horizonNodes.addChildNode(cityNode)
        horizonNodes.addChildNode(peaksNode)
        horizonNodes.addChildNode(centralSkylineNode)
        horizonNodes.addChildNode(horizonLineNode)

        buildCoreHorizonComposition()
        buildCoastLayer()
        buildCityLayer(parent: coastNode, count: quality == .efficiency ? 8 : 12, spread: 540, baseline: -8, heightScale: 0.38, alpha: 0.18)
        buildCityLayer(parent: cityNode, count: quality == .efficiency ? 22 : quality == .balanced ? 34 : 46, spread: 900, baseline: -4, heightScale: 1.0, alpha: 0.92)
        buildMountainRange(parent: coastNode, peaks: quality == .efficiency ? 6 : 8, spread: 950, baseY: -18, maxHeight: 74, offset: 0)
        buildMountainRange(parent: peaksNode, peaks: quality == .efficiency ? 11 : quality == .balanced ? 16 : 23, spread: 1_160, baseY: -12, maxHeight: 230, offset: 41)
        buildAurora(parent: peaksNode)
    }

    private func buildCoreHorizonComposition() {
        buildFacetedMountains(side: -1)
        buildFacetedMountains(side: 1)
        buildCentralSkyline()
        let horizonMaterial = Self.constantMaterial(UIColor.cyan, emission: UIColor.cyan, transparency: 0.88)
        horizonLineMaterials.append(horizonMaterial)
        let horizon = Self.cylinderLine(from: SCNVector3(-650, -30, -42), to: SCNVector3(650, -30, -42), radius: 0.48, material: horizonMaterial)
        horizon.name = "cyan-grid-horizon-glow"
        horizonLineNode.addChildNode(horizon)
    }

    private func buildCentralSkyline() {
        let widths: [CGFloat] = [18, 28, 22, 36, 20, 46, 26, 18, 34, 24, 44, 28, 20, 38, 22, 30, 18]
        let heights: [CGFloat] = [36, 58, 46, 88, 52, 104, 62, 42, 78, 48, 96, 68, 44, 82, 50, 64, 40]
        let skylineMaterial = Self.opaqueConstantMaterial(
            UIColor(red: 0.078, green: 0.039, blue: 0.165, alpha: 1),
            emission: UIColor(red: 0.018, green: 0.004, blue: 0.026, alpha: 1)
        )
        centralSkylineFillMaterials.append(skylineMaterial)
        let rimMaterial = Self.constantMaterial(
            UIColor(red: 1, green: 0.12, blue: 0.68, alpha: 1),
            emission: UIColor(red: 1, green: 0.12, blue: 0.68, alpha: 1),
            transparency: 0.78
        )
        centralSkylineRimMaterials.append(rimMaterial)
        var x: Float = -315
        let towerCount = switch quality {
        case .efficiency: 9
        case .balanced: 13
        case .fidelity: widths.count
        }
        for index in 0..<towerCount {
            let width = widths[index]
            let height = heights[index]
            let tower = SCNNode(geometry: SCNBox(width: width, height: height, length: 10, chamferRadius: 0))
            tower.name = "flat-topped-dark-polygon-tower"
            tower.geometry?.materials = [skylineMaterial]
            tower.position = SCNVector3(x + Float(width * 0.5), -30 + Float(height * 0.5), Float(-35 - (index % 4) * 2))
            centralSkylineNode.addChildNode(tower)
            addSparseWindows(to: tower, width: width, height: height, seed: index)
            let rim = Self.cylinderLine(
                from: SCNVector3(x, -30 + Float(height) + 0.3, tower.position.z + 5.7),
                to: SCNVector3(x + Float(width), -30 + Float(height) + 0.3, tower.position.z + 5.7),
                radius: 0.16,
                material: rimMaterial
            )
            rim.name = "subtle-magenta-tower-rim"
            centralSkylineNode.addChildNode(rim)
            x += Float(width + CGFloat(8 + (index % 3) * 3))
        }
    }

    private func addSparseWindows(to tower: SCNNode, width: CGFloat, height: CGFloat, seed: Int) {
        let colors = [
            UIColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1),
            UIColor(red: 1.0, green: 0.12, blue: 0.62, alpha: 1),
            UIColor(red: 1.0, green: 0.55, blue: 0.14, alpha: 1)
        ]
        let material = Self.constantMaterial(colors[seed % colors.count], emission: colors[seed % colors.count], transparency: 0.72)
        let columns = max(1, Int(width / 8))
        let rows = max(2, Int(height / 14))
        for row in 0..<rows {
            for column in 0..<columns where (row * 3 + column + seed) % 4 == 0 {
                let window = SCNNode(geometry: SCNPlane(width: 1.25, height: 2.0))
                window.name = "sparse-neon-skyline-window"
                window.geometry?.materials = [material]
                let x = -Float(width * 0.36) + Float(column) * Float(width * 0.72) / Float(max(columns - 1, 1))
                let y = -Float(height * 0.38) + Float(row) * Float(height * 0.70) / Float(max(rows - 1, 1))
                window.position = SCNVector3(x, y, Float(5.12))
                tower.addChildNode(window)
            }
        }
    }

    private func buildFacetedMountains(side: Int) {
        let baseStart: Float = side < 0 ? -650 : 70
        let baseEnd: Float = side < 0 ? -70 : 650
        let baseY: Float = -31
        let z: Float = -59
        let shades = [
            Self.opaqueConstantMaterial(UIColor(red: 0.090, green: 0.034, blue: 0.190, alpha: 1), emission: UIColor(red: 0.010, green: 0.002, blue: 0.030, alpha: 1)),
            Self.opaqueConstantMaterial(UIColor(red: 0.120, green: 0.045, blue: 0.240, alpha: 1), emission: UIColor(red: 0.014, green: 0.003, blue: 0.036, alpha: 1)),
            Self.opaqueConstantMaterial(UIColor(red: 0.145, green: 0.055, blue: 0.285, alpha: 1), emission: UIColor(red: 0.016, green: 0.004, blue: 0.045, alpha: 1))
        ]
        let edge = Self.constantMaterial(UIColor(red: 0.95, green: 0.14, blue: 1, alpha: 1), emission: UIColor(red: 0.95, green: 0.14, blue: 1, alpha: 1), transparency: 0.72)
        facetedMountainEdgeMaterials.append(edge)
        let peaks: [(Float, Float)] = side < 0
            ? [(-610, 36), (-500, 18), (-370, 48), (-255, 26), (-120, 58)]
            : [(118, 58), (238, 30), (360, 50), (505, 20), (620, 44)]
        let bases = side < 0
            ? [baseStart, -550, -440, -315, -190, baseEnd]
            : [baseStart, 180, 300, 435, 565, baseEnd]
        for index in 0..<(bases.count - 1) {
            let left = bases[index]
            let right = bases[index + 1]
            let peak = peaks[min(index, peaks.count - 1)]
            let triangle = SCNNode(geometry: Self.triangleGeometry(
                SCNVector3(left, baseY, z),
                SCNVector3(right, baseY, z - Float(index % 2) * 1.5),
                SCNVector3(peak.0, peak.1, z - 1.0)
            ))
            triangle.name = side < 0 ? "left-solid-faceted-violet-ridge" : "right-solid-faceted-violet-ridge"
            triangle.geometry?.materials = [shades[index % shades.count]]
            facetedMountainNode.addChildNode(triangle)
            facetedMountainNode.addChildNode(Self.cylinderLine(from: SCNVector3(left, baseY, z + 0.2), to: SCNVector3(peak.0, peak.1, z + 0.2), radius: 0.13, material: edge))
            facetedMountainNode.addChildNode(Self.cylinderLine(from: SCNVector3(peak.0, peak.1, z + 0.2), to: SCNVector3(right, baseY, z + 0.2), radius: 0.13, material: edge))
        }
        let baseLine = Self.cylinderLine(from: SCNVector3(baseStart, baseY, z + 0.3), to: SCNVector3(baseEnd, baseY, z + 0.3), radius: 0.13, material: edge)
        facetedMountainNode.addChildNode(baseLine)
    }

    private func buildCoastLayer() {
        let oceanMaterial = Self.constantMaterial(
            UIColor(red: 0.01, green: 0.20, blue: 0.28, alpha: 1),
            emission: UIColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1),
            transparency: 0.62
        )
        oceanMaterials.append(oceanMaterial)
        for index in 0..<5 {
            let y = Float(-28 - index * 8)
            let halfWidth = Float(450 + index * 80)
            let z = Float(-Float(index) * 1.5)
            let wave = Self.cylinderLine(
                from: SCNVector3(-halfWidth, y, z),
                to: SCNVector3(halfWidth, y + Float((index % 2) * 3), z),
                radius: 0.32,
                material: oceanMaterial
            )
            wave.name = "coast-glowing-wave-line"
            coastNode.addChildNode(wave)
        }
        for side in [-1, 1] {
            for index in 0..<(quality == .efficiency ? 3 : 5) {
                let palm = makePalm(seed: UInt64(index * 31 + (side < 0 ? 7 : 19)))
                palm.scale = SCNVector3(0.72, 0.72, 0.72)
                palm.position = SCNVector3(Float(side * (250 + index * 72)), Float(-44 + index % 2 * 4), Float(-8 - index * 4))
                coastNode.addChildNode(palm)
            }
        }
    }

    private func buildCityLayer(parent: SCNNode, count: Int, spread: Float, baseline: Float, heightScale: CGFloat, alpha: CGFloat) {
        let variants = (0..<5).map { index in
            let material = Self.constantMaterial(
                UIColor(red: 0.020, green: 0.012, blue: 0.045, alpha: 1),
                emission: Self.buildingWindowTexture(variant: index, theme: .neonCity),
                transparency: 1
            )
            skylineMaterials.append(material)
            return material
        }
        for index in 0..<count {
            let normalized = Float(index) / Float(max(count - 1, 1))
            let width = CGFloat(15 + ((index * 19) % 28))
            let height = CGFloat(42 + ((index * 47) % 150)) * heightScale
            let depth = CGFloat(10 + ((index * 11) % 18))
            let building = SCNNode(geometry: SCNBox(width: width, height: height, length: depth, chamferRadius: 0.0))
            building.name = "distant-neon-building"
            building.geometry?.materials = [variants[index % variants.count]]
            let xJitter = Float(((index * 53) % 37) - 18)
            building.position = SCNVector3(-spread * 0.5 + spread * normalized + xJitter, baseline + Float(height * 0.5), Float(-18 - (index % 6) * 7))
            parent.addChildNode(building)
        }
    }

    private func buildMountainRange(parent: SCNNode, peaks: Int, spread: Float, baseY: Float, maxHeight: Float, offset: Int) {
        var points: [SCNVector3] = []
        for index in 0..<peaks {
            let x = -spread * 0.5 + spread * Float(index) / Float(max(peaks - 1, 1))
            let selector = (index * 73 + offset) % 100
            let y = baseY + Float(12 + selector) / 100 * min(maxHeight, 86)
            points.append(SCNVector3(x, y, Float(-34 - (index % 3) * 4)))
        }

        let fill = SCNNode(geometry: Self.mountainFillGeometry(points: points, baseY: baseY - 18))
        fill.name = "dark-mountain-fill"
        fill.geometry?.materials = [Self.opaqueConstantMaterial(UIColor(red: 0.048, green: 0.022, blue: 0.105, alpha: 1), emission: UIColor(red: 0.010, green: 0.002, blue: 0.024, alpha: 1))]
        parent.addChildNode(fill)

        let lineMaterial = Self.constantMaterial(UIColor(red: 0.86, green: 0.16, blue: 1, alpha: 1), emission: UIColor(red: 0.86, green: 0.16, blue: 1, alpha: 1), transparency: 0.54)
        mountainLineMaterials.append(lineMaterial)
        for index in 0..<(points.count - 1) {
            let line = Self.cylinderLine(from: points[index], to: points[index + 1], radius: 0.22, material: lineMaterial)
            line.name = "wireframe-mountain-ridge"
            parent.addChildNode(line)
            if index.isMultiple(of: 2) {
                let rib = Self.cylinderLine(
                    from: points[index],
                    to: SCNVector3(points[index].x + (points[index + 1].x - points[index].x) * 0.42, baseY - 15, points[index].z),
                    radius: 0.12,
                    material: lineMaterial
                )
                rib.name = "wireframe-mountain-rib"
                parent.addChildNode(rib)
            }
        }
    }

    private func buildAurora(parent: SCNNode) {
        auroraNode.name = "midnight-aurora-ribbons"
        let colors = [
            UIColor(red: 0.25, green: 1, blue: 0.78, alpha: 1),
            UIColor(red: 0.42, green: 0.52, blue: 1, alpha: 1),
            UIColor(red: 0.85, green: 0.25, blue: 1, alpha: 1)
        ]
        let ribbonCount = quality == .efficiency ? 1 : 3
        for index in 0..<ribbonCount {
            let ribbon = Self.softRibbonImage(color: colors[index])
            let material = Self.constantMaterial(.white, emission: ribbon, transparency: 0.34)
            material.diffuse.contents = ribbon
            material.transparent.contents = ribbon
            material.writesToDepthBuffer = false
            auroraMaterials.append(material)
            let plane = SCNNode(geometry: SCNPlane(width: CGFloat(470 - index * 45), height: CGFloat(22 + index * 7)))
            plane.name = "aurora-glow-ribbon"
            plane.geometry?.materials = [material]
            plane.position = SCNVector3(Float(index * 60 - 60), Float(152 + index * 26), Float(-68 - index * 8))
            plane.eulerAngles.z = Float(-0.10 + Double(index) * 0.08)
            auroraNode.addChildNode(plane)
        }
        parent.addChildNode(auroraNode)
    }

    private func buildAtmosphere() {
        hazeNode.name = "horizon-haze-bands"
        for index in 0..<3 {
            let material = Self.constantMaterial(UIColor.magenta, emission: UIColor.magenta, transparency: 0.07)
            material.writesToDepthBuffer = false
            hazeMaterials.append(material)
            let band = SCNNode(geometry: SCNPlane(width: CGFloat(1_100 + index * 180), height: CGFloat(34 + index * 18)))
            band.geometry?.materials = [material]
            band.position = SCNVector3(0, Float(-18 + index * 18), Float(-52 - index * 9))
            hazeNode.addChildNode(band)
        }
        horizonNodes.addChildNode(hazeNode)
    }

    private func applyTheme(_ theme: EnvironmentTheme3D, animated: Bool) {
        let duration = animated ? 3.0 : 0.0
        if let scene {
            if animated { SCNTransaction.begin(); SCNTransaction.animationDuration = duration }
            configureScene(scene, theme: theme)
            installLights(on: scene)
            if animated { SCNTransaction.commit() }
        }

        let transaction = {
            self.coastNode.opacity = theme.id == "sunset-coast" ? 1 : (theme.id == "neon-city" ? 0.28 : 0.12)
            self.cityNode.opacity = theme.id == "neon-city" ? 1 : (theme.id == "sunset-coast" ? 0.10 : 0.16)
            self.peaksNode.opacity = theme.id == "midnight-peaks" ? 1 : (theme.id == "neon-city" ? 0.28 : 0.14)
            self.centralSkylineNode.opacity = (theme.id == "midnight-peaks" ? 0.55 : 1.0) * self.renderSceneryOpacityScale
            self.facetedMountainNode.opacity = theme.id == "neon-city" ? 0.48 : 0.70
            self.horizonLineNode.opacity = self.highContrast ? 1.0 : 0.78
            self.auroraNode.opacity = theme.id == "midnight-peaks" ? (self.reduceMotion ? 0.42 : 0.70) : 0.05
            self.hazeNode.opacity = self.highContrast ? 0.16 : theme.hazeOpacity
            self.starNode.opacity = theme.starOpacity
            self.sunNode.opacity = theme.sunOpacity
            self.magentaGridNode.opacity = theme.magentaGridOpacity
            self.gridNode.opacity = self.highContrast ? 0.95 : theme.gridOpacity
        }

        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            transaction()
            SCNTransaction.commit()
        } else {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            transaction()
            SCNTransaction.commit()
        }

        applyMaterials(theme)
    }

    private func applyMaterials(_ theme: EnvironmentTheme3D) {
        let visuals = assets(for: theme)
        let contrastBoost: CGFloat = highContrast ? 1.28 : 1
        let fogAlpha: CGFloat = highContrast ? 0.06 : 0.10
        let cyan = theme.gridCyan.brightened(amount: contrastBoost)
        let magenta = theme.gridMagenta.brightened(amount: contrastBoost)
        for material in gridMaterials {
            material.diffuse.contents = cyan
            material.emission.contents = cyan
        }
        for material in magentaGridMaterials {
            material.diffuse.contents = magenta
            material.emission.contents = magenta
        }
        for material in starMaterials {
            let star = theme.starColor.brightened(amount: contrastBoost)
            material.diffuse.contents = star
            material.emission.contents = star
        }
        for material in groundMaterials {
            material.diffuse.contents = Self.groundGradient
            material.emission.contents = UIColor(red: 0.012, green: 0.004, blue: 0.030, alpha: 1)
        }
        for material in warmHorizonGlowMaterials {
            material.diffuse.contents = visuals.horizonGlow
            material.emission.contents = visuals.horizonGlow
            material.transparent.contents = visuals.horizonGlow
        }
        for material in centralSkylineFillMaterials {
            material.diffuse.contents = UIColor(red: 0.078, green: 0.039, blue: 0.165, alpha: 1)
            material.emission.contents = UIColor(red: 0.012, green: 0.002, blue: 0.020, alpha: 1)
        }
        for material in centralSkylineRimMaterials {
            let rim = theme.gridMagenta.brightened(amount: highContrast ? 1.25 : 1.0)
            material.diffuse.contents = rim
            material.emission.contents = rim
        }
        for material in facetedMountainFillMaterials {
            material.diffuse.contents = visuals.mountain
            material.emission.contents = UIColor(red: 0.016, green: 0.004, blue: 0.040, alpha: 1)
        }
        for material in facetedMountainEdgeMaterials {
            let edge = theme.mountainLine.brightened(amount: highContrast ? 1.3 : 1.05)
            material.diffuse.contents = edge
            material.emission.contents = edge
        }
        for material in horizonLineMaterials {
            material.diffuse.contents = cyan
            material.emission.contents = cyan
        }
        for material in mountainLineMaterials {
            let line = theme.mountainLine.brightened(amount: contrastBoost)
            material.diffuse.contents = line
            material.emission.contents = line
        }
        for material in oceanMaterials {
            material.diffuse.contents = theme.oceanLine.withAlphaComponent(0.55)
            material.emission.contents = theme.oceanLine.brightened(amount: contrastBoost)
        }
        for material in auroraMaterials {
            material.transparency = reduceMotion ? 0.24 : (highContrast ? 0.42 : 0.34)
        }
        for material in hazeMaterials {
            material.diffuse.contents = theme.fogColor.withAlphaComponent(fogAlpha)
            material.emission.contents = theme.fogColor.withAlphaComponent(fogAlpha)
        }
        sunDiscNode.geometry?.materials = [visuals.sunDisc]
        sunHaloNode.geometry?.materials = [visuals.sunHalo]
    }

    private func assets(for theme: EnvironmentTheme3D) -> ThemeAssets {
        let key = "\(theme.id)-\(highContrast)"
        if let cached = themeAssets[key] { return cached }
        let made = ThemeAssets(
            sky: Self.skyGradientImage(theme: theme, highContrast: highContrast),
            horizonGlow: Self.horizonBandGlowImage(color: theme.horizonGlow),
            mountain: Self.mountainGradientImage(theme: theme, highContrast: highContrast),
            sunDisc: Self.sunDiscMaterial(theme: theme, highContrast: highContrast),
            sunHalo: Self.sunHaloMaterial(theme: theme, highContrast: highContrast)
        )
        themeAssets[key] = made
        return made
    }

    private func updateGrid(cameraPosition: SCNVector3, speedRatio: Double) {
        let snappedX = (cameraPosition.x / gridCellSize).rounded(.down) * gridCellSize
        let snappedZ = (cameraPosition.z / gridCellSize).rounded(.down) * gridCellSize
        let gridY = (groundLevel ?? (cameraPosition.y - 7.4)) - 0.35
        gridNode.position = SCNVector3(snappedX, gridY, snappedZ)
        magentaGridNode.position = gridNode.position
        groundNode.position = SCNVector3(snappedX, gridY - 0.08, snappedZ)
        let fade = Float(min(max(speedRatio, 0), 1.25))
        let baseOpacity = highContrast ? CGFloat(0.95) : currentTheme.gridOpacity
        let speedOpacity = CGFloat(0.86 + fade * 0.12)
        gridNode.opacity = baseOpacity * speedOpacity
    }

    private func updateHorizon(cameraPosition: SCNVector3) {
        let target = cameraPosition.nrAdding(horizonForward.nrScaled(by: 650))
        horizonNodes.position = SCNVector3(target.x, cameraPosition.y + 18, target.z)
        horizonNodes.look(at: SCNVector3(cameraPosition.x, cameraPosition.y + 18, cameraPosition.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    }

    private func updateSun(cameraPosition: SCNVector3, time: TimeInterval, speedRatio: Double) {
        sunNode.position = SCNVector3(0, currentTheme.sunHeight - 7, -132)
        sunNode.look(at: cameraPosition, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
        guard !reduceMotion else {
            sunNode.opacity = currentTheme.sunOpacity
            return
        }
        let shimmer = 0.035 * sin(time * (0.9 + speedRatio * 0.35))
        sunDiscNode.scale = SCNVector3(1 + Float(shimmer), 1 - Float(shimmer * 0.5), 1)
        sunHaloNode.opacity = 0.62 + CGFloat(0.08 * sin(time * 0.7))
    }

    private func updateStars(cameraPosition: SCNVector3, time: TimeInterval) {
        starNode.position.y = 0
        guard !reduceMotion, quality != .efficiency else { return }
        for (index, star) in starNode.childNodes.enumerated() where index % 5 == 0 {
            star.opacity = 0.45 + CGFloat(0.22 * sin(time * 0.55 + Double(index)))
        }
    }

    private func updateMotionEffects(time: TimeInterval, speedRatio: Double) {
        guard !reduceMotion else { return }
        let speed = min(max(speedRatio, 0), 1.4)
        hazeNode.position.x = Float(sin(time * 0.08) * 24)
        auroraNode.position.x = Float(sin(time * 0.11) * 18)
        auroraNode.opacity = (currentTheme.id == "midnight-peaks" ? 0.66 : 0.05) + CGFloat(speed * 0.04)
    }

    private func buildEyeCandy() {
        eyeCandyRoot.name = "ambient-aaa-eye-candy-root"
        horizonNodes.addChildNode(eyeCandyRoot)
        buildHoverTraffic()
        buildBlimp()
        buildSearchlights()
        buildMeteors()
        buildMaglev()
        buildCityHolograms()
        buildFireworks()
        buildCoastEyeCandy()
        buildPeaksEyeCandy()
        buildLightning()
    }

    private func buildHoverTraffic() {
        let count = switch quality {
        case .efficiency: 2
        case .balanced: 4
        case .fidelity: 7
        }
        for index in 0..<count {
            let cyan = UIColor(red: 0.0, green: 0.92, blue: 1.0, alpha: 1)
            let hot = UIColor(red: 1.0, green: 0.12, blue: 0.64, alpha: 1)
            let bodyMaterial = Self.constantMaterial(index.isMultiple(of: 2) ? cyan : hot, emission: index.isMultiple(of: 2) ? cyan : hot, transparency: 0.9)
            let trailMaterial = Self.constantMaterial(.white, emission: Self.linearGlowImage(color: index.isMultiple(of: 2) ? cyan : hot), transparency: 0.25)
            trailMaterial.diffuse.contents = Self.linearGlowImage(color: index.isMultiple(of: 2) ? cyan : hot)
            trailMaterial.transparent.contents = trailMaterial.diffuse.contents
            trailMaterial.writesToDepthBuffer = false

            let vehicle = SCNNode()
            vehicle.name = "ambient-hover-vehicle"
            let body = SCNNode(geometry: SCNBox(width: 8.2, height: 1.6, length: 2.7, chamferRadius: 0.5))
            body.geometry?.materials = [bodyMaterial]
            body.position.y = 0.4
            vehicle.addChildNode(body)
            let canopy = SCNNode(geometry: SCNSphere(radius: 1.15))
            canopy.scale = SCNVector3(1.8, 0.42, 0.7)
            canopy.position = SCNVector3(-0.7, 1.35, 0)
            canopy.geometry?.materials = [Self.constantMaterial(UIColor(red: 0.02, green: 0.04, blue: 0.09, alpha: 1), emission: cyan, transparency: 0.62)]
            vehicle.addChildNode(canopy)
            let trail = SCNNode(geometry: SCNPlane(width: 18, height: 0.65))
            trail.geometry?.materials = [trailMaterial]
            trail.position = SCNVector3(27, 0.25, 0)
            vehicle.addChildNode(trail)
            eyeCandyRoot.addChildNode(vehicle)
            hoverActors.append(EyeCandyActor3D(node: vehicle, secondary: trail, seed: Float(index * 37 + 9), period: TimeInterval(10 + index * 3)))
        }
    }

    private func buildBlimp() {
        blimpNode.name = "neon-lit-airship-holographic-ad"
        let shellColor = UIColor(red: 0.10, green: 0.05, blue: 0.24, alpha: 1)
        let shell = SCNNode(geometry: SCNSphere(radius: 11.5))
        shell.scale = SCNVector3(2.9, 0.72, 0.72)
        shell.geometry?.materials = [Self.constantMaterial(shellColor, emission: UIColor(red: 0.28, green: 0.08, blue: 0.45, alpha: 1), transparency: 0.95)]
        blimpNode.addChildNode(shell)
        let stripeMaterial = Self.constantMaterial(.cyan, emission: UIColor(red: 0, green: 0.96, blue: 1, alpha: 1), transparency: 0.86)
        for x in [-19.0, -7.0, 7.0, 19.0] {
            let stripe = SCNNode(geometry: SCNTorus(ringRadius: 5.2, pipeRadius: 0.08))
            stripe.geometry?.materials = [stripeMaterial]
            stripe.position.x = Float(x)
            stripe.eulerAngles.y = .pi / 2
            stripe.scale = SCNVector3(1, 0.42, 0.42)
            blimpNode.addChildNode(stripe)
        }
        let gondola = SCNNode(geometry: SCNBox(width: 13, height: 2.4, length: 2.2, chamferRadius: 0.35))
        gondola.position = SCNVector3(0, -7.2, 0)
        gondola.geometry?.materials = [Self.constantMaterial(UIColor(red: 0.02, green: 0.012, blue: 0.06, alpha: 1), emission: UIColor(red: 1, green: 0.16, blue: 0.66, alpha: 1), transparency: 0.95)]
        blimpNode.addChildNode(gondola)
        let labels = ["NOVA FUEL", "VANTA PORT", "LUMA WAVE"]
        for (index, label) in labels.enumerated() {
            let text = SCNText(string: label, extrusionDepth: 0.025)
            text.font = UIFont.monospacedSystemFont(ofSize: 1.1, weight: .bold)
            text.flatness = 0.08
            text.materials = [Self.constantMaterial(.white, emission: index.isMultiple(of: 2) ? UIColor.cyan : UIColor.magenta, transparency: 1)]
            let textNode = SCNNode(geometry: text)
            textNode.name = "airship-scrolling-hologram-ad"
            textNode.scale = SCNVector3(0.32, 0.32, 0.32)
            textNode.position = SCNVector3(-8.4, -8.55, 1.25)
            textNode.opacity = index == 0 ? 1 : 0
            blimpNode.addChildNode(textNode)
            blimpAdNodes.append(textNode)
        }
        blimpNode.position = SCNVector3(-320, 216, -96)
        eyeCandyRoot.addChildNode(blimpNode)
    }

    private func buildSearchlights() {
        let count = quality == .efficiency ? 2 : 4
        for index in 0..<count {
            let color = index.isMultiple(of: 2) ? UIColor(red: 0, green: 0.78, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.18, blue: 0.70, alpha: 1)
            let beamImage = Self.searchlightBeamImage(color: color)
            let beamMaterial = Self.constantMaterial(.white, emission: beamImage, transparency: 0.34)
            beamMaterial.diffuse.contents = beamImage
            beamMaterial.transparent.contents = beamImage
            beamMaterial.writesToDepthBuffer = false
            let beam = SCNNode(geometry: SCNPlane(width: 190, height: 10))
            beam.name = "thin-soft-neon-searchlight-beam"
            beam.geometry?.materials = [beamMaterial]
            beam.position = SCNVector3(Float(index * 170 - 255), 78, -84)
            beam.eulerAngles = SCNVector3(0, 0, Float(-0.34 + Double(index) * 0.17))
            eyeCandyRoot.addChildNode(beam)
            searchlightActors.append(EyeCandyActor3D(node: beam, seed: Float(index * 43 + 5), period: TimeInterval(8 + index)))
        }
    }

    private func buildMeteors() {
        let count = quality == .fidelity ? 3 : 2
        for index in 0..<count {
            let color = index.isMultiple(of: 2) ? UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1) : UIColor(red: 0.55, green: 0.90, blue: 1, alpha: 1)
            let material = Self.constantMaterial(.white, emission: Self.linearGlowImage(color: color), transparency: 0.82)
            material.diffuse.contents = Self.linearGlowImage(color: color)
            material.transparent.contents = material.diffuse.contents
            material.writesToDepthBuffer = false
            let meteor = SCNNode(geometry: SCNPlane(width: 72, height: 3.3))
            meteor.name = "shooting-star-meteor-trail"
            meteor.geometry?.materials = [material]
            meteor.eulerAngles.z = -0.34
            meteor.opacity = 0
            eyeCandyRoot.addChildNode(meteor)
            meteorActors.append(EyeCandyActor3D(node: meteor, seed: Float(19 + index * 71), period: TimeInterval(17 + index * 9)))
        }
    }

    private func buildMaglev() {
        maglevNode.name = "distant-elevated-maglev-train"
        let trackMaterial = Self.constantMaterial(.cyan, emission: UIColor(red: 0, green: 0.88, blue: 1, alpha: 1), transparency: 0.72)
        let railA = Self.cylinderLine(from: SCNVector3(-460, 70, -58), to: SCNVector3(460, 72, -58), radius: 0.28, material: trackMaterial)
        let railB = Self.cylinderLine(from: SCNVector3(-460, 65, -58), to: SCNVector3(460, 67, -58), radius: 0.14, material: trackMaterial)
        maglevNode.addChildNode(railA)
        maglevNode.addChildNode(railB)
        let carMaterial = Self.constantMaterial(UIColor(red: 0.03, green: 0.04, blue: 0.11, alpha: 1), emission: UIColor(red: 1, green: 0.16, blue: 0.66, alpha: 1), transparency: 0.98)
        for index in 0..<5 {
            let car = SCNNode(geometry: SCNBox(width: 24, height: 5, length: 5.2, chamferRadius: 1.1))
            car.name = "maglev-glowing-car"
            car.geometry?.materials = [carMaterial]
            car.position = SCNVector3(Float(index * -29), 70, -58)
            maglevNode.addChildNode(car)
            maglevCars.append(car)
        }
        cityNode.addChildNode(maglevNode)
    }

    private func buildCityHolograms() {
        let logos = ["VANTA", "AXIS", "ORBIT"]
        for (index, logo) in logos.enumerated() {
            let node = SCNNode()
            node.name = "giant-city-hologram-\(logo)"
            let ring = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(8 + index * 2), pipeRadius: 0.22))
            let color = index.isMultiple(of: 2) ? UIColor.cyan : UIColor.magenta
            ring.geometry?.materials = [Self.constantMaterial(color, emission: color, transparency: 0.58)]
            node.addChildNode(ring)
            let text = SCNText(string: logo, extrusionDepth: 0.04)
            text.font = UIFont.monospacedSystemFont(ofSize: 1.5, weight: .heavy)
            text.flatness = 0.08
            text.materials = [Self.constantMaterial(.white, emission: color, transparency: 0.78)]
            let textNode = SCNNode(geometry: text)
            textNode.scale = SCNVector3(0.55, 0.55, 0.55)
            textNode.position = SCNVector3(Float(-4 - index), -2, 0.8)
            node.addChildNode(textNode)
            node.position = SCNVector3(Float(index * 175 - 180), Float(116 + index * 18), Float(-66 - index * 8))
            cityNode.addChildNode(node)
            hologramActors.append(EyeCandyActor3D(node: node, seed: Float(index * 101 + 3), period: TimeInterval(5 + index)))
        }
    }

    private func buildFireworks() {
        let count = quality == .efficiency ? 2 : quality == .balanced ? 4 : 6
        for index in 0..<count {
            let burst = SCNNode()
            burst.name = "sunset-coast-horizon-firework-burst"
            let color = index.isMultiple(of: 2) ? UIColor(red: 1, green: 0.72, blue: 0.18, alpha: 1) : UIColor(red: 1, green: 0.16, blue: 0.72, alpha: 1)
            let material = Self.constantMaterial(color, emission: color, transparency: 0.78)
            material.writesToDepthBuffer = false
            let rayCount = quality == .efficiency ? 8 : 12
            for ray in 0..<rayCount {
                let angle = Float(ray) / Float(rayCount) * .pi * 2
                let end = SCNVector3(cos(angle) * 18, sin(angle) * 18, 0)
                burst.addChildNode(Self.cylinderLine(from: SCNVector3(0, 0, 0), to: end, radius: 0.18, material: material))
            }
            burst.position = SCNVector3(Float(index * 125 - 310), Float(92 + (index % 3) * 23), -64)
            burst.opacity = 0
            coastNode.addChildNode(burst)
            fireworkActors.append(EyeCandyActor3D(node: burst, seed: Float(index * 31 + 11), period: TimeInterval(6 + index * 2)))
        }
    }

    private func buildCoastEyeCandy() {
        let count = quality == .efficiency ? 2 : 4
        for index in 0..<count {
            let boat = SCNNode()
            boat.name = index.isMultiple(of: 2) ? "neon-sailboat-on-glowing-ocean" : "glowing-dolphin-wave-arc"
            let color = index.isMultiple(of: 2) ? UIColor(red: 1, green: 0.22, blue: 0.72, alpha: 1) : UIColor(red: 0, green: 0.95, blue: 1, alpha: 1)
            let material = Self.constantMaterial(color, emission: color, transparency: 0.76)
            if index.isMultiple(of: 2) {
                boat.addChildNode(Self.cylinderLine(from: SCNVector3(-9, 0, 0), to: SCNVector3(9, 0, 0), radius: 0.16, material: material))
                boat.addChildNode(Self.cylinderLine(from: SCNVector3(0, 0, 0), to: SCNVector3(0, 9, 0), radius: 0.10, material: material))
                boat.addChildNode(Self.cylinderLine(from: SCNVector3(0, 8.6, 0), to: SCNVector3(5.5, 1.1, 0), radius: 0.08, material: material))
            } else {
                let torus = SCNNode(geometry: SCNTorus(ringRadius: 7, pipeRadius: 0.25))
                torus.scale = SCNVector3(1, 0.42, 0.08)
                torus.geometry?.materials = [material]
                boat.addChildNode(torus)
            }
            boat.position = SCNVector3(Float(index * 155 - 300), Float(-42 + index * 4), Float(-12 - index * 2))
            coastNode.addChildNode(boat)
            coastCandyActors.append(EyeCandyActor3D(node: boat, seed: Float(index * 29 + 13), period: TimeInterval(14 + index * 4)))
        }
    }

    private func buildPeaksEyeCandy() {
        let count = quality == .efficiency ? 2 : 4
        for index in 0..<count {
            let ufo = SCNNode()
            ufo.name = "midnight-ufo-satellite-light-formation"
            let color = index.isMultiple(of: 2) ? UIColor(red: 0.50, green: 1, blue: 0.78, alpha: 1) : UIColor(red: 0.58, green: 0.52, blue: 1, alpha: 1)
            let material = Self.constantMaterial(color, emission: color, transparency: 0.72)
            let ring = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(9 + index * 2), pipeRadius: 0.22))
            ring.geometry?.materials = [material]
            ufo.addChildNode(ring)
            for dot in 0..<5 {
                let sphere = SCNNode(geometry: SCNSphere(radius: 0.85))
                sphere.geometry?.materials = [material]
                let angle = Float(dot) / 5 * .pi * 2
                sphere.position = SCNVector3(cos(angle) * Float(10 + index * 2), sin(angle) * Float(5 + index), 0)
                ufo.addChildNode(sphere)
            }
            let beamMaterial = Self.constantMaterial(color, emission: color, transparency: 0.12)
            beamMaterial.writesToDepthBuffer = false
            let beam = SCNNode(geometry: SCNCone(topRadius: 9, bottomRadius: 1, height: 95))
            beam.geometry?.materials = [beamMaterial]
            beam.position.y = -50
            ufo.addChildNode(beam)
            ufo.position = SCNVector3(Float(index * 180 - 260), Float(178 + index * 14), Float(-72 - index * 6))
            peaksNode.addChildNode(ufo)
            satelliteActors.append(EyeCandyActor3D(node: ufo, seed: Float(index * 47 + 23), period: TimeInterval(11 + index * 3)))
        }
    }

    private func buildLightning() {
        lightningNode.name = "distant-accessibility-gated-lightning"
        for index in 0..<2 {
            let material = Self.constantMaterial(.white, emission: UIColor(red: 0.78, green: 0.86, blue: 1, alpha: 1), transparency: 0.0)
            lightningMaterials.append(material)
            var start = SCNVector3(Float(index * 260 - 160), 205, -70)
            for segment in 0..<5 {
                let end = SCNVector3(start.x + Float((segment.isMultiple(of: 2) ? 1 : -1) * (18 + segment * 4)), start.y - Float(22 + segment * 4), start.z)
                lightningNode.addChildNode(Self.cylinderLine(from: start, to: end, radius: 0.45, material: material))
                start = end
            }
        }
        peaksNode.addChildNode(lightningNode)
    }

    private func updateEyeCandy(time: TimeInterval, speedRatio: Double) {
        let coastActive = currentTheme.id == "sunset-coast"
        let cityActive = currentTheme.id == "neon-city"
        let peaksActive = currentTheme.id == "midnight-peaks"
        eyeCandyRoot.opacity = (highContrast ? 0.86 : 1) * renderSceneryOpacityScale
        updateHoverTraffic(time: time, speedRatio: speedRatio)
        updateBlimp(time: time, active: cityActive || coastActive)
        updateSearchlights(time: time, active: cityActive || peaksActive)
        updateMeteors(time: time)
        updateMaglev(time: time, active: cityActive)
        updateCityHolograms(time: time, active: cityActive)
        updateFireworks(time: time, active: coastActive)
        updateCoastEyeCandy(time: time, active: coastActive)
        updatePeaksEyeCandy(time: time, active: peaksActive)
        updateLightning(time: time, active: peaksActive || cityActive)
    }

    private func updateHoverTraffic(time: TimeInterval, speedRatio: Double) {
        for (index, actor) in hoverActors.enumerated() {
            let progress = actor.progress(at: time)
            let direction: Float = index.isMultiple(of: 2) ? 1 : -1
            let x = direction * (-620 + 1_240 * Float(progress))
            let y = Float(132 + index * 19) + Float(sin(time * 0.55 + Double(actor.seed)) * 13)
            actor.node.position = SCNVector3(x, y, Float(-78 - index * 8))
            actor.node.eulerAngles.z = Float(sin(time * 0.7 + Double(index)) * 0.08)
            actor.node.eulerAngles.y = direction > 0 ? .pi : 0
            let baseOpacity: CGFloat = reduceMotion ? 0.34 : 0.68
            actor.node.opacity = baseOpacity * CGFloat(0.82 + min(max(speedRatio, 0), 1.2) * 0.12)
            actor.secondary?.opacity = reduceMotion ? 0.03 : 0.10
        }
    }

    private func updateBlimp(time: TimeInterval, active: Bool) {
        let baseX = reduceMotion ? -250 : Float(sin(time * 0.045) * 360)
        blimpNode.position = SCNVector3(baseX, 220 + Float(sin(time * 0.08) * 10), -98)
        blimpNode.opacity = active ? 0.86 : 0.18
        guard !blimpAdNodes.isEmpty else { return }
        let selected = Int(time / 2.2) % blimpAdNodes.count
        for (index, ad) in blimpAdNodes.enumerated() {
            ad.opacity = index == selected ? 1 : 0
            if !reduceMotion {
                ad.position.x = -10.5 + Float((time * 2.4).truncatingRemainder(dividingBy: 5.0))
            }
        }
    }

    private func updateSearchlights(time: TimeInterval, active: Bool) {
        for (index, actor) in searchlightActors.enumerated() {
            let sweep = reduceMotion ? 0 : Float(sin(time * (0.20 + Double(index) * 0.035) + Double(actor.seed)) * 0.42)
            actor.node.eulerAngles.z = Float(-0.36 + Double(index) * 0.19) + sweep
            actor.node.opacity = active ? (highContrast ? 0.08 : 0.16) : 0.025
        }
    }

    private func updateMeteors(time: TimeInterval) {
        guard !reduceFlashing else {
            meteorActors.forEach { $0.node.opacity = 0 }
            return
        }
        for (index, actor) in meteorActors.enumerated() {
            let progress = actor.progress(at: time)
            let active = progress < 0.16
            let local = Float(progress / 0.16)
            actor.node.position = SCNVector3(560 - local * 1_100, Float(275 - local * 95 - Float(index * 22)), Float(-100 - index * 8))
            actor.node.opacity = active ? CGFloat(sin(Double(local) * .pi)) * 0.9 : 0
        }
    }

    private func updateMaglev(time: TimeInterval, active: Bool) {
        maglevNode.opacity = active ? 0.92 : 0.10
        let progress = reduceMotion ? Float(0.35) : Float((time.truncatingRemainder(dividingBy: 13.0)) / 13.0)
        let x = -420 + 840 * progress
        for (index, car) in maglevCars.enumerated() {
            car.position.x = x - Float(index * 29)
        }
    }

    private func updateCityHolograms(time: TimeInterval, active: Bool) {
        for (index, actor) in hologramActors.enumerated() {
            actor.node.eulerAngles.y = reduceMotion ? 0 : Float(sin(time * 0.12 + Double(index)) * 0.16)
            let flicker = reduceFlashing ? 1 : (0.78 + 0.22 * sin(time * 9.0 + Double(actor.seed)))
            actor.node.opacity = active ? CGFloat(flicker) * 0.34 : 0.025
        }
    }

    private func updateFireworks(time: TimeInterval, active: Bool) {
        guard active, !reduceFlashing else {
            fireworkActors.forEach { $0.node.opacity = 0 }
            return
        }
        for actor in fireworkActors {
            let progress = actor.progress(at: time)
            let burst = max(0, 1 - abs(progress - 0.18) / 0.18)
            actor.node.scale = SCNVector3(0.35 + Float(progress) * 2.2, 0.35 + Float(progress) * 2.2, 1)
            actor.node.opacity = CGFloat(burst) * (highContrast ? 0.55 : 0.92)
        }
    }

    private func updateCoastEyeCandy(time: TimeInterval, active: Bool) {
        for (index, actor) in coastCandyActors.enumerated() {
            let progress = actor.progress(at: time)
            let x = -420 + 840 * Float(progress)
            actor.node.position.x = index.isMultiple(of: 2) ? x : -x
            actor.node.position.y = Float(-45 + index * 5) + (reduceMotion ? 0 : Float(sin(time * 0.8 + Double(index)) * 3))
            actor.node.opacity = active ? 0.72 : 0.05
        }
    }

    private func updatePeaksEyeCandy(time: TimeInterval, active: Bool) {
        for (index, actor) in satelliteActors.enumerated() {
            if !reduceMotion {
                actor.node.eulerAngles.z = Float(time * 0.12 + Double(index))
                actor.node.position.x += Float(sin(time * 0.09 + Double(index)) * 0.04)
            }
            actor.node.opacity = active ? 0.76 : 0.06
        }
    }

    private func updateLightning(time: TimeInterval, active: Bool) {
        let canFlash = active && !reduceFlashing
        let pulse = canFlash ? max(0, sin(time * 0.95) - 0.92) / 0.08 : 0
        let opacity = CGFloat(min(max(pulse, 0), 1)) * (highContrast ? 0.45 : 0.86)
        lightningNode.opacity = opacity
        for material in lightningMaterials {
            material.transparency = opacity
        }
    }

    private func makePalm(seed: UInt64) -> SCNNode {
        let node = SCNNode()
        node.name = "roadside-neon-palm"
        let trunkMaterial = Self.constantMaterial(
            UIColor(red: 0.07, green: 0.025, blue: 0.09, alpha: 1),
            emission: UIColor(red: 1, green: 0.18, blue: 0.78, alpha: 1),
            transparency: 0.95
        )
        let leafMaterial = Self.constantMaterial(
            UIColor(red: 0.02, green: 0.10, blue: 0.10, alpha: 1),
            emission: UIColor(red: 0.0, green: 0.95, blue: 0.78, alpha: 1),
            transparency: 0.90
        )
        let height = Float(7.5 + Double(seed % 7) * 0.45)
        let trunk = Self.cylinderLine(from: SCNVector3(0, 0, 0), to: SCNVector3(Float(seed % 3) * 0.18 - 0.18, height, 0), radius: 0.12, material: trunkMaterial)
        node.addChildNode(trunk)
        for index in 0..<7 {
            let angle = Float(index) / 7 * .pi * 2 + Float(seed % 11) * 0.04
            let length = Float(2.2 + Double((seed + UInt64(index)) % 5) * 0.24)
            let end = SCNVector3(cos(angle) * length, height + sin(Float(index)) * 0.18, sin(angle) * length * 0.45)
            let leaf = Self.cylinderLine(from: SCNVector3(0, height, 0), to: end, radius: 0.055, material: leafMaterial)
            node.addChildNode(leaf)
        }
        let planterGlow = SCNNode(geometry: SCNTorus(ringRadius: 1.05, pipeRadius: 0.045))
        planterGlow.geometry?.materials = [leafMaterial]
        planterGlow.position.y = 0.06
        node.addChildNode(planterGlow)
        let trunkBands = max(3, Int(seed % 4) + 3)
        for band in 0..<trunkBands {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.18, pipeRadius: 0.025))
            ring.geometry?.materials = [trunkMaterial]
            ring.position.y = Float(band + 1) * height / Float(trunkBands + 1)
            node.addChildNode(ring)
        }
        return node
    }

    private func makeSign(seed: UInt64) -> SCNNode {
        let node = SCNNode()
        node.name = "roadside-stacked-holo-billboard"
        let postMaterial = Self.constantMaterial(
            UIColor(red: 0.018, green: 0.016, blue: 0.055, alpha: 1),
            emission: UIColor(red: 0.08, green: 0.42, blue: 0.55, alpha: 1),
            transparency: 1
        )
        let panelCount = 2 + Int(seed % 2)
        let totalHeight = Float(panelCount) * 2.45 + 4.2
        node.addChildNode(Self.cylinderLine(from: SCNVector3(-1.95, 0, 0), to: SCNVector3(-1.95, totalHeight, 0), radius: 0.075, material: postMaterial))
        node.addChildNode(Self.cylinderLine(from: SCNVector3(1.95, 0, 0), to: SCNVector3(1.95, totalHeight, 0), radius: 0.075, material: postMaterial))
        node.addChildNode(Self.cylinderLine(from: SCNVector3(-2.3, 0.05, 0), to: SCNVector3(2.3, 0.05, 0), radius: 0.06, material: postMaterial))

        let copySets: [(String, String, HoloBillboardStyle3D)] = [
            ("RE-GEN", "RECLAIM YOUR\\nPOTENTIAL", .medical),
            ("CONSUME", "PRODUCT X", .warning),
            ("OBEY", "THE ALGORITHM", .authority),
            ("EYE-NET", "IS ALWAYS\\nWATCHING", .surveillance),
            ("JPC", "BIOMEDICAL", .medical),
            ("M. ALEE", "RACE LDR  1:42", .scoreboard),
            ("C. CORE", "T. REK   M. AX", .scoreboard)
        ]
        let colors = [
            UIColor(red: 0.0, green: 0.94, blue: 1.0, alpha: 1),
            UIColor(red: 1.0, green: 0.56, blue: 0.16, alpha: 1),
            UIColor(red: 1.0, green: 0.14, blue: 0.68, alpha: 1)
        ]
        for panelIndex in 0..<panelCount {
            let selected = copySets[Int((seed + UInt64(panelIndex * 3)) % UInt64(copySets.count))]
            let border = colors[Int((seed + UInt64(panelIndex)) % UInt64(colors.count))]
            let panel = makeBillboardPanel(
                title: selected.0,
                subtitle: selected.1,
                style: selected.2,
                borderColor: border,
                width: 8.8,
                height: panelIndex == 0 && panelCount == 3 ? 1.85 : 2.15
            )
            panel.position = SCNVector3(0, 3.55 + Float(panelIndex) * 2.45, 0)
            node.addChildNode(panel)
        }
        let transformer = SCNNode(geometry: SCNBox(width: 0.7, height: 0.34, length: 0.28, chamferRadius: 0.04))
        transformer.name = "billboard-power-cell"
        transformer.geometry?.materials = [Self.constantMaterial(.darkGray, emission: UIColor(red: 0, green: 0.85, blue: 1, alpha: 1), transparency: 1)]
        transformer.position = SCNVector3(0, 2.16, 0)
        node.addChildNode(transformer)
        return node
    }

    private func makeBillboardPanel(title: String, subtitle: String, style: HoloBillboardStyle3D, borderColor: UIColor, width: CGFloat, height: CGFloat) -> SCNNode {
        let node = SCNNode()
        node.name = "framed-neon-holo-ad-panel"
        let key = BillboardTextureKey(title: title, subtitle: subtitle, style: style, borderColor: borderColor)
        let faceImage: UIImage
        if let cached = billboardTextures[key] {
            faceImage = cached
        } else {
            let made = Self.billboardTexture(title: title, subtitle: subtitle, style: style, borderColor: borderColor)
            billboardTextures[key] = made
            faceImage = made
        }
        let faceMaterial = Self.constantMaterial(UIColor(red: 0.012, green: 0.010, blue: 0.050, alpha: 1), emission: faceImage, transparency: 1)
        faceMaterial.diffuse.contents = faceImage
        faceMaterial.transparent.contents = faceImage
        faceMaterial.blendMode = .alpha
        faceMaterial.writesToDepthBuffer = false
        let face = SCNNode(geometry: SCNPlane(width: width, height: height))
        face.geometry?.materials = [faceMaterial]
        face.position.z = 0.055
        node.addChildNode(face)

        let tubeMaterial = Self.constantMaterial(borderColor, emission: borderColor, transparency: 0.96)
        let horizontal = CGFloat(0.13)
        for y in [-height * 0.5, height * 0.5] {
            let tube = SCNNode(geometry: SCNBox(width: width + horizontal, height: horizontal, length: 0.16, chamferRadius: 0.055))
            tube.geometry?.materials = [tubeMaterial]
            tube.position = SCNVector3(0, Float(y), 0.11)
            node.addChildNode(tube)
        }
        for x in [-width * 0.5, width * 0.5] {
            let tube = SCNNode(geometry: SCNBox(width: horizontal, height: height + horizontal, length: 0.16, chamferRadius: 0.055))
            tube.geometry?.materials = [tubeMaterial]
            tube.position = SCNVector3(Float(x), 0, 0.11)
            node.addChildNode(tube)
        }
        let back = SCNNode(geometry: SCNBox(width: width + 0.18, height: height + 0.18, length: 0.10, chamferRadius: 0.08))
        back.geometry?.materials = [Self.constantMaterial(UIColor(red: 0.010, green: 0.008, blue: 0.035, alpha: 1), emission: borderColor.withAlphaComponent(0.16), transparency: 0.95)]
        back.position.z = -0.04
        node.addChildNode(back)
        return node
    }

    private func makeLightPole(seed: UInt64) -> SCNNode {
        let node = SCNNode()
        node.name = "roadside-neon-light-pole"
        let poleMaterial = Self.constantMaterial(.darkGray, emission: UIColor(red: 0.12, green: 0.22, blue: 0.38, alpha: 1), transparency: 1)
        let lampColor = seed.isMultiple(of: 2) ? UIColor.cyan : UIColor.magenta
        let lampMaterial = Self.constantMaterial(lampColor, emission: lampColor, transparency: 1)
        node.addChildNode(Self.cylinderLine(from: SCNVector3(0, 0, 0), to: SCNVector3(0, 6.2, 0), radius: 0.07, material: poleMaterial))
        node.addChildNode(Self.cylinderLine(from: SCNVector3(0, 6.2, 0), to: SCNVector3(1.4, 6.55, 0), radius: 0.045, material: poleMaterial))
        let lamp = SCNNode(geometry: SCNSphere(radius: 0.24))
        lamp.geometry?.materials = [lampMaterial]
        lamp.position = SCNVector3(1.58, 6.58, 0)
        node.addChildNode(lamp)
        return node
    }

    private func makeRelayBeacon(seed: UInt64) -> SCNNode {
        let node = SCNNode()
        node.name = "roadside-midnight-relay-beacon"
        let cold = UIColor(red: 0.42, green: 0.78, blue: 1, alpha: 1)
        let hot = UIColor(red: 0.55, green: 1, blue: 0.78, alpha: 1)
        let lineMaterial = Self.constantMaterial(cold, emission: cold, transparency: 0.96)
        let coreMaterial = Self.constantMaterial(hot, emission: hot, transparency: 1)
        let height: Float = 8.6
        let feet = [SCNVector3(-0.9, 0, -0.55), SCNVector3(0.9, 0, -0.55), SCNVector3(0, 0, 0.85)]
        for foot in feet {
            node.addChildNode(Self.cylinderLine(from: foot, to: SCNVector3(0, height, 0), radius: 0.045, material: lineMaterial))
        }
        for y in stride(from: Float(1.7), through: height - 1, by: 1.7) {
            node.addChildNode(Self.cylinderLine(from: SCNVector3(-0.62, y, -0.35), to: SCNVector3(0.62, y, -0.35), radius: 0.035, material: lineMaterial))
        }
        let core = SCNNode(geometry: SCNSphere(radius: 0.36 + CGFloat(seed % 3) * 0.03))
        core.geometry?.materials = [coreMaterial]
        core.position = SCNVector3(0, height + 0.45, 0)
        node.addChildNode(core)
        return node
    }

    private func makeTunnelRing(seed: UInt64) -> SCNNode {
        let node = SCNNode()
        node.name = "roadside-neon-city-tunnel-ring"
        let color = seed.isMultiple(of: 2) ? UIColor(red: 0, green: 0.95, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.15, blue: 0.65, alpha: 1)
        let material = Self.constantMaterial(color, emission: color, transparency: 0.92)
        let width: Float = 13
        let height: Float = 7.4
        node.addChildNode(Self.cylinderLine(from: SCNVector3(-width * 0.5, 0, 0), to: SCNVector3(-width * 0.5, height, 0), radius: 0.08, material: material))
        node.addChildNode(Self.cylinderLine(from: SCNVector3(width * 0.5, 0, 0), to: SCNVector3(width * 0.5, height, 0), radius: 0.08, material: material))
        node.addChildNode(Self.cylinderLine(from: SCNVector3(-width * 0.5, height, 0), to: SCNVector3(width * 0.5, height, 0), radius: 0.08, material: material))
        for index in 0..<4 {
            let x = -width * 0.5 + Float(index + 1) * width / 5
            node.addChildNode(Self.cylinderLine(from: SCNVector3(x, height, 0), to: SCNVector3(x - 1.1, height - 1.2, 0), radius: 0.035, material: material))
        }
        return node
    }

    private func makeRetroTower(seed: UInt64) -> SCNNode {
        let node = SCNNode()
        node.name = "roadside-retro-futurist-neon-tower"
        let coreColor = seed.isMultiple(of: 2) ? UIColor(red: 0, green: 0.88, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.16, blue: 0.68, alpha: 1)
        let darkMaterial = Self.constantMaterial(UIColor(red: 0.018, green: 0.014, blue: 0.055, alpha: 1), emission: UIColor(red: 0.05, green: 0.03, blue: 0.12, alpha: 1), transparency: 0.98)
        let neonMaterial = Self.constantMaterial(coreColor, emission: coreColor, transparency: 0.90)
        let height = Float(10 + (seed % 5))
        let shaft = SCNNode(geometry: SCNCylinder(radius: 0.72, height: CGFloat(height)))
        shaft.geometry?.materials = [darkMaterial]
        shaft.position.y = height * 0.5
        node.addChildNode(shaft)
        for y in stride(from: Float(1.5), through: height - 1, by: 2.0) {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 1.05, pipeRadius: 0.045))
            ring.geometry?.materials = [neonMaterial]
            ring.position.y = y
            node.addChildNode(ring)
        }
        let crown = SCNNode(geometry: SCNSphere(radius: 0.98))
        crown.scale = SCNVector3(1.45, 0.56, 1.45)
        crown.position.y = height + 0.85
        crown.geometry?.materials = [neonMaterial]
        node.addChildNode(crown)
        let antenna = Self.cylinderLine(from: SCNVector3(0, height + 1.2, 0), to: SCNVector3(0, height + 3.6, 0), radius: 0.04, material: neonMaterial)
        node.addChildNode(antenna)
        let signPanel = SCNNode(geometry: SCNBox(width: 3.3, height: 1.1, length: 0.11, chamferRadius: 0.08))
        signPanel.position = SCNVector3(0, height * 0.62, 0.84)
        signPanel.geometry?.materials = [neonMaterial]
        node.addChildNode(signPanel)
        return node
    }

    private static func cylinderLine(from: SCNVector3, to: SCNVector3, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let delta = to.nrSubtracting(from)
        let length = delta.nrLength
        let node = SCNNode(geometry: SCNCylinder(radius: radius, height: CGFloat(length)))
        node.geometry?.materials = [material]
        node.position = from.nrAdding(delta.nrScaled(by: 0.5))
        guard length > 0.0001 else { return node }
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(delta.x / length, delta.y / length, delta.z / length))
        return node
    }

    private static func mountainFillGeometry(points: [SCNVector3], baseY: Float) -> SCNGeometry {
        guard points.count >= 2 else { return SCNGeometry() }
        let vertices = [SCNVector3(points[0].x, baseY, points[0].z)] + points + [SCNVector3(points.last!.x, baseY, points.last!.z)]
        let bottomRightIndex = Int32(vertices.count - 1)
        var indices: [Int32] = []
        for index in 1..<(vertices.count - 2) {
            indices.append(0)
            indices.append(Int32(index))
            indices.append(Int32(index + 1))
        }
        indices.append(0)
        indices.append(Int32(vertices.count - 2))
        indices.append(bottomRightIndex)
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [source], elements: [element])
    }

    private static func opaqueConstantMaterial(_ diffuse: UIColor, emission: Any) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = diffuse
        material.emission.contents = emission
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.transparency = 1
        material.blendMode = .alpha
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        return material
    }

    private static func constantMaterial(_ diffuse: UIColor, emission: Any, transparency: CGFloat = 1) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = diffuse
        material.emission.contents = emission
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.transparency = transparency
        material.blendMode = transparency < 1 ? .add : .alpha
        return material
    }

    private static func sunDiscMaterial(theme: EnvironmentTheme3D, highContrast: Bool) -> SCNMaterial {
        let image = stripedSunImage(top: theme.sunTop, bottom: theme.sunBottom, highContrast: highContrast)
        let material = constantMaterial(.white, emission: image, transparency: 1)
        material.diffuse.contents = image
        material.transparent.contents = image
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        return material
    }

    private static func sunHaloMaterial(theme: EnvironmentTheme3D, highContrast: Bool) -> SCNMaterial {
        let image = radialGlowImage(color: theme.sunHalo, highContrast: highContrast)
        let material = constantMaterial(.white, emission: image, transparency: highContrast ? 0.54 : 0.72)
        material.diffuse.contents = image
        material.transparent.contents = image
        material.blendMode = .add
        material.writesToDepthBuffer = false
        return material
    }

    private static func skyGradientImage(theme: EnvironmentTheme3D, highContrast: Bool) -> UIImage {
        let size = CGSize(width: 8, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [
                (highContrast ? theme.skyTop.darker(amount: 0.20) : theme.skyTop).cgColor,
                UIColor(red: 0.090, green: 0.020, blue: 0.220, alpha: 1).cgColor,
                theme.skyMid.cgColor,
                theme.skyBottom.cgColor,
                theme.horizonGlow.brightened(amount: highContrast ? 0.80 : 1.10).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, 0.42, 0.68, 0.86, 1]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    private static func stripedSunImage(top: UIColor, bottom: UIColor, highContrast: Bool) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            cg.clear(rect)
            cg.addEllipse(in: rect.insetBy(dx: 18, dy: 18))
            cg.clip()
            let orange = UIColor(red: 1.0, green: 0.55, blue: 0.10, alpha: 1)
            let colors = [
                top.brightened(amount: highContrast ? 1.15 : 1).cgColor,
                orange.cgColor,
                bottom.cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.48, 1])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 18), end: CGPoint(x: 0, y: size.height - 18), options: [])
            cg.setBlendMode(.clear)
            let gaps: [CGFloat] = [12, 15, 19, 25, 33, 43]
            var y: CGFloat = size.height * 0.52
            for gap in gaps {
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: gap))
                y += gap + 19
            }
        }
    }

    private static func radialGlowImage(color: UIColor, highContrast: Bool) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let colors = [
                color.withAlphaComponent(highContrast ? 0.42 : 0.58).cgColor,
                color.withAlphaComponent(highContrast ? 0.18 : 0.26).cgColor,
                color.withAlphaComponent(0).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.38, 1])!
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 8, endCenter: center, endRadius: size.width / 2, options: [])
        }
    }

    private static func triangleGeometry(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3) -> SCNGeometry {
        let source = SCNGeometrySource(vertices: [a, b, c])
        let element = SCNGeometryElement(indices: [Int32(0), 1, 2], primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.isDoubleSided = true
        return geometry
    }

    private static func triangleGeometry(width: CGFloat, height: CGFloat) -> SCNGeometry {
        let halfWidth = Float(width * 0.5)
        let vertices = [
            SCNVector3(-halfWidth, 0, 0),
            SCNVector3(halfWidth, 0, 0),
            SCNVector3(0, Float(height), 0)
        ]
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: [Int32(0), 1, 2], primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        return geometry
    }

    private static func horizonBandGlowImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 1_024, height: 192)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
            let colors = [
                UIColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 0.55).cgColor,
                color.withAlphaComponent(0.34).cgColor,
                UIColor(red: 1.0, green: 0.10, blue: 0.62, alpha: 0.18).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.28, 0.62, 1])!
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 12, endCenter: center, endRadius: size.width * 0.58, options: [])
        }
    }

    private static func searchlightBeamImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 48)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let vertical = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.clear.cgColor, color.withAlphaComponent(0.20).cgColor, UIColor.clear.cgColor] as CFArray,
                locations: [0, 0.5, 1]
            )!
            cg.drawLinearGradient(vertical, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            cg.setBlendMode(.destinationIn)
            let horizontal = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [color.withAlphaComponent(0.80).cgColor, color.withAlphaComponent(0.22).cgColor, UIColor.clear.cgColor] as CFArray,
                locations: [0, 0.45, 1]
            )!
            cg.drawLinearGradient(horizontal, start: CGPoint(x: 0, y: size.height / 2), end: CGPoint(x: size.width, y: size.height / 2), options: [])
        }
    }

    /// Soft band that fades out at the top/bottom and both ends so sky ribbons read as glow, not slabs.
    private static func softRibbonImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 256, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let vertical = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [color.withAlphaComponent(0).cgColor, color.withAlphaComponent(0.85).cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 0.5, 1]
            )!
            cg.drawLinearGradient(vertical, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            cg.setBlendMode(.destinationIn)
            let horizontal = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(white: 1, alpha: 0).cgColor, UIColor.white.cgColor, UIColor.white.cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                locations: [0, 0.25, 0.75, 1]
            )!
            cg.drawLinearGradient(horizontal, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
        }
    }

    private static func linearGlowImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 256, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [
                color.withAlphaComponent(0).cgColor,
                color.withAlphaComponent(0.78).cgColor,
                color.withAlphaComponent(0.22).cgColor,
                color.withAlphaComponent(0).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.24, 0.72, 1])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height / 2), end: CGPoint(x: size.width, y: size.height / 2), options: [])
        }
    }

    private static func groundGradientImage() -> UIImage {
        let size = CGSize(width: 16, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [
                UIColor(red: 0.102, green: 0.043, blue: 0.228, alpha: 1).cgColor,
                UIColor(red: 0.055, green: 0.024, blue: 0.125, alpha: 1).cgColor,
                UIColor(red: 0.028, green: 0.014, blue: 0.070, alpha: 1).cgColor
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.52, 1])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])
        }
    }

    private static func mountainGradientImage(theme: EnvironmentTheme3D, highContrast: Bool) -> UIImage {
        let size = CGSize(width: 256, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let top = theme.mountainLine.withAlphaComponent(highContrast ? 0.62 : 0.44)
            let bottom = UIColor(red: 0.030, green: 0.012, blue: 0.090, alpha: 1)
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            cg.setStrokeColor(UIColor(red: 0.95, green: 0.25, blue: 1, alpha: highContrast ? 0.42 : 0.20).cgColor)
            cg.setLineWidth(2)
            for x in stride(from: 20, through: 240, by: 44) {
                cg.move(to: CGPoint(x: CGFloat(x), y: 0))
                cg.addLine(to: CGPoint(x: CGFloat(x - 58), y: size.height))
            }
            cg.strokePath()
        }
    }

    private static func billboardTexture(title: String, subtitle: String, style: HoloBillboardStyle3D, borderColor: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            cg.setFillColor(UIColor(red: 0.020, green: 0.012, blue: 0.055, alpha: 0.92).cgColor)
            cg.fill(rect)
            cg.setFillColor(borderColor.withAlphaComponent(0.12).cgColor)
            cg.fill(CGRect(x: 10, y: 10, width: size.width - 20, height: size.height - 20))
            cg.setStrokeColor(borderColor.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(3)
            for y in stride(from: 24, through: Int(size.height) - 20, by: 18) {
                cg.move(to: CGPoint(x: 18, y: CGFloat(y)))
                cg.addLine(to: CGPoint(x: size.width - 18, y: CGFloat(y)))
            }
            cg.strokePath()

            let iconRect = CGRect(x: 30, y: 36, width: 86, height: 86)
            drawBillboardIcon(style: style, in: iconRect, color: borderColor, context: cg)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: style == .scoreboard ? 32 : 38, weight: .heavy),
                .foregroundColor: UIColor(red: 0.82, green: 0.96, blue: 1.0, alpha: 1)
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: style == .scoreboard ? 24 : 25, weight: .bold),
                .foregroundColor: borderColor.brightened(amount: 1.15)
            ]
            let titleRect = CGRect(x: 136, y: style == .scoreboard ? 28 : 30, width: 350, height: 52)
            title.draw(in: titleRect, withAttributes: titleAttributes)
            let subtitleRect = CGRect(x: 136, y: 82, width: 350, height: 82)
            subtitle.draw(in: subtitleRect, withAttributes: subtitleAttributes)

            if style == .scoreboard {
                let names = ["M. ALEE", "C. CORE", "T. REK", "M. AX"]
                for (index, name) in names.enumerated() {
                    let y = 82 + index * 20
                    name.draw(in: CGRect(x: 136, y: y, width: 115, height: 22), withAttributes: subtitleAttributes)
                    String(format: "%02d:%02d", 1 + index, 39 + index).draw(in: CGRect(x: 280, y: y, width: 100, height: 22), withAttributes: subtitleAttributes)
                }
            }
        }
    }

    private static func drawBillboardIcon(style: HoloBillboardStyle3D, in rect: CGRect, color: UIColor, context cg: CGContext) {
        cg.saveGState()
        cg.setStrokeColor(color.cgColor)
        cg.setFillColor(color.withAlphaComponent(0.18).cgColor)
        cg.setLineWidth(5)
        switch style {
        case .medical:
            cg.strokeEllipse(in: rect.insetBy(dx: 10, dy: 10))
            cg.fill(CGRect(x: rect.midX - 8, y: rect.minY + 20, width: 16, height: rect.height - 40))
            cg.fill(CGRect(x: rect.minX + 20, y: rect.midY - 8, width: rect.width - 40, height: 16))
        case .warning:
            cg.move(to: CGPoint(x: rect.midX, y: rect.minY + 8))
            cg.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - 8))
            cg.addLine(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 8))
            cg.closePath()
            cg.drawPath(using: .fillStroke)
        case .authority:
            cg.stroke(CGRect(x: rect.minX + 12, y: rect.minY + 16, width: rect.width - 24, height: rect.height - 32))
            cg.move(to: CGPoint(x: rect.minX + 16, y: rect.midY))
            cg.addLine(to: CGPoint(x: rect.maxX - 16, y: rect.midY))
            cg.strokePath()
        case .surveillance:
            cg.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            cg.addQuadCurve(to: CGPoint(x: rect.maxX - 4, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.minY + 6))
            cg.addQuadCurve(to: CGPoint(x: rect.minX + 4, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.maxY - 6))
            cg.drawPath(using: .fillStroke)
            cg.strokeEllipse(in: rect.insetBy(dx: 30, dy: 30))
        case .scoreboard:
            for index in 0..<4 {
                cg.strokeEllipse(in: CGRect(x: rect.minX + CGFloat(index % 2) * 42 + 8, y: rect.minY + CGFloat(index / 2) * 42 + 8, width: 28, height: 28))
            }
        }
        cg.restoreGState()
    }

    private static func buildingWindowTexture(variant: Int, theme: EnvironmentTheme3D) -> UIImage {
        let size = CGSize(width: 128, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(red: 0.01, green: 0.012, blue: 0.04, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            let windowColor = (variant.isMultiple(of: 2) ? UIColor(red: 0, green: 0.95, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.20, blue: 0.62, alpha: 1)).cgColor
            cg.setFillColor(windowColor)
            for row in 0..<14 {
                for col in 0..<5 where (row + col + variant) % 3 != 0 {
                    let rect = CGRect(x: 14 + col * 21, y: 28 + row * 15, width: 9, height: 5)
                    cg.fill(rect)
                }
            }
            cg.setFillColor(UIColor(red: 1, green: 0.22, blue: 0.70, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: 12 + variant * 4, width: Int(size.width), height: 4))
        }
    }
}

private enum HoloBillboardStyle3D: Hashable {
    case medical
    case warning
    case authority
    case surveillance
    case scoreboard
}

private final class EyeCandyActor3D {
    let node: SCNNode
    let secondary: SCNNode?
    let seed: Float
    let period: TimeInterval

    init(node: SCNNode, secondary: SCNNode? = nil, seed: Float, period: TimeInterval) {
        self.node = node
        self.secondary = secondary
        self.seed = seed
        self.period = max(period, 0.1)
    }

    func progress(at time: TimeInterval) -> Double {
        var value = (time + TimeInterval(seed)).truncatingRemainder(dividingBy: period) / period
        if value < 0 { value += 1 }
        return value
    }
}

private struct EnvironmentTheme3D: Equatable {
    let id: String
    let skyTop: UIColor
    let skyMid: UIColor
    let skyBottom: UIColor
    let horizonGlow: UIColor
    let fogColor: UIColor
    let fogStart: Double
    let fogEnd: Double
    let sunTop: UIColor
    let sunBottom: UIColor
    let sunHalo: UIColor
    let sunHeight: Float
    let sunOpacity: CGFloat
    let gridCyan: UIColor
    let gridMagenta: UIColor
    let gridOpacity: CGFloat
    let magentaGridOpacity: CGFloat
    let mountainLine: UIColor
    let oceanLine: UIColor
    let starColor: UIColor
    let starOpacity: CGFloat
    let hazeOpacity: CGFloat
    let ambientLight: UIColor
    let directionalLight: UIColor

    static let sunsetCoast = EnvironmentTheme3D(
        id: "sunset-coast",
        skyTop: UIColor(red: 0.035, green: 0.008, blue: 0.145, alpha: 1),
        skyMid: UIColor(red: 0.19, green: 0.04, blue: 0.34, alpha: 1),
        skyBottom: UIColor(red: 0.70, green: 0.08, blue: 0.48, alpha: 1),
        horizonGlow: UIColor(red: 1.00, green: 0.36, blue: 0.18, alpha: 1),
        fogColor: UIColor(red: 0.72, green: 0.16, blue: 0.52, alpha: 1),
        fogStart: 260,
        fogEnd: 920,
        sunTop: UIColor(red: 1.00, green: 0.88, blue: 0.20, alpha: 1),
        sunBottom: UIColor(red: 1.00, green: 0.18, blue: 0.62, alpha: 1),
        sunHalo: UIColor(red: 1.00, green: 0.28, blue: 0.46, alpha: 1),
        sunHeight: 58,
        sunOpacity: 0.96,
        gridCyan: UIColor(red: 0.00, green: 0.90, blue: 1.00, alpha: 1),
        gridMagenta: UIColor(red: 1.00, green: 0.10, blue: 0.72, alpha: 1),
        gridOpacity: 0.76,
        magentaGridOpacity: 0.58,
        mountainLine: UIColor(red: 0.78, green: 0.20, blue: 1.0, alpha: 1),
        oceanLine: UIColor(red: 0.0, green: 0.82, blue: 1.0, alpha: 1),
        starColor: UIColor(red: 0.72, green: 0.88, blue: 1, alpha: 1),
        starOpacity: 0.48,
        hazeOpacity: 0.32,
        ambientLight: UIColor(red: 0.36, green: 0.18, blue: 0.50, alpha: 1),
        directionalLight: UIColor(red: 1.0, green: 0.55, blue: 0.72, alpha: 1)
    )

    static let neonCity = EnvironmentTheme3D(
        id: "neon-city",
        skyTop: UIColor(red: 0.012, green: 0.016, blue: 0.09, alpha: 1),
        skyMid: UIColor(red: 0.04, green: 0.06, blue: 0.20, alpha: 1),
        skyBottom: UIColor(red: 0.22, green: 0.08, blue: 0.35, alpha: 1),
        horizonGlow: UIColor(red: 0.0, green: 0.46, blue: 0.72, alpha: 1),
        fogColor: UIColor(red: 0.10, green: 0.22, blue: 0.40, alpha: 1),
        fogStart: 220,
        fogEnd: 840,
        sunTop: UIColor(red: 1.0, green: 0.58, blue: 0.20, alpha: 1),
        sunBottom: UIColor(red: 1.0, green: 0.10, blue: 0.64, alpha: 1),
        sunHalo: UIColor(red: 0.0, green: 0.65, blue: 0.95, alpha: 1),
        sunHeight: 46,
        sunOpacity: 0.58,
        gridCyan: UIColor(red: 0.0, green: 0.96, blue: 1.0, alpha: 1),
        gridMagenta: UIColor(red: 1.0, green: 0.18, blue: 0.70, alpha: 1),
        gridOpacity: 0.70,
        magentaGridOpacity: 0.72,
        mountainLine: UIColor(red: 0.46, green: 0.28, blue: 1, alpha: 1),
        oceanLine: UIColor(red: 0.15, green: 0.72, blue: 1, alpha: 1),
        starColor: UIColor(red: 0.80, green: 0.96, blue: 1, alpha: 1),
        starOpacity: 0.34,
        hazeOpacity: 0.48,
        ambientLight: UIColor(red: 0.18, green: 0.24, blue: 0.44, alpha: 1),
        directionalLight: UIColor(red: 0.38, green: 0.78, blue: 1.0, alpha: 1)
    )

    static let midnightPeaks = EnvironmentTheme3D(
        id: "midnight-peaks",
        skyTop: UIColor(red: 0.004, green: 0.012, blue: 0.070, alpha: 1),
        skyMid: UIColor(red: 0.018, green: 0.040, blue: 0.135, alpha: 1),
        skyBottom: UIColor(red: 0.05, green: 0.13, blue: 0.25, alpha: 1),
        horizonGlow: UIColor(red: 0.24, green: 0.19, blue: 0.62, alpha: 1),
        fogColor: UIColor(red: 0.38, green: 0.32, blue: 0.70, alpha: 1),
        fogStart: 250,
        fogEnd: 900,
        sunTop: UIColor(red: 0.74, green: 0.92, blue: 1.0, alpha: 1),
        sunBottom: UIColor(red: 0.38, green: 0.42, blue: 1.0, alpha: 1),
        sunHalo: UIColor(red: 0.40, green: 0.62, blue: 1.0, alpha: 1),
        sunHeight: 72,
        sunOpacity: 0.48,
        gridCyan: UIColor(red: 0.40, green: 0.92, blue: 1.0, alpha: 1),
        gridMagenta: UIColor(red: 0.50, green: 0.35, blue: 1.0, alpha: 1),
        gridOpacity: 0.58,
        magentaGridOpacity: 0.48,
        mountainLine: UIColor(red: 0.56, green: 0.38, blue: 1.0, alpha: 1),
        oceanLine: UIColor(red: 0.28, green: 0.62, blue: 1.0, alpha: 1),
        starColor: UIColor(red: 0.88, green: 0.96, blue: 1.0, alpha: 1),
        starOpacity: 0.92,
        hazeOpacity: 0.28,
        ambientLight: UIColor(red: 0.16, green: 0.20, blue: 0.40, alpha: 1),
        directionalLight: UIColor(red: 0.58, green: 0.74, blue: 1.0, alpha: 1)
    )

    static func theme(for environmentID: String) -> EnvironmentTheme3D {
        switch environmentID.lowercased() {
        case "neon-city": return neonCity
        case "midnight-peaks": return midnightPeaks
        case "sunset-coast": return sunsetCoast
        default:
            if environmentID.lowercased().contains("city") { return neonCity }
            if environmentID.lowercased().contains("peak") || environmentID.lowercased().contains("summit") { return midnightPeaks }
            return sunsetCoast
        }
    }
}

private extension SCNNode {
    func removeFromParentNodeReturningSelf() -> SCNNode {
        removeFromParentNode()
        return self
    }

    var worldPosition: SCNVector3 {
        let transform = worldTransform
        return SCNVector3(transform.m41, transform.m42, transform.m43)
    }

    var forwardVectorFlattened: SCNVector3 {
        let transform = worldTransform
        return SCNVector3(-transform.m31, 0, -transform.m33).nrNormalized(default: SCNVector3(0, 0, -1))
    }
}

private extension SCNVector3 {
    var nrLength: Float { sqrt(x * x + y * y + z * z) }

    func nrAdding(_ other: SCNVector3) -> SCNVector3 {
        SCNVector3(x + other.x, y + other.y, z + other.z)
    }

    func nrSubtracting(_ other: SCNVector3) -> SCNVector3 {
        SCNVector3(x - other.x, y - other.y, z - other.z)
    }

    func nrScaled(by value: Float) -> SCNVector3 {
        SCNVector3(x * value, y * value, z * value)
    }

    func nrNormalized(default fallback: SCNVector3) -> SCNVector3 {
        let length = nrLength
        guard length > 0.0001 else { return fallback }
        return nrScaled(by: 1 / length)
    }

    func nrLerped(to other: SCNVector3, t: Float) -> SCNVector3 {
        SCNVector3(
            x + (other.x - x) * t,
            y + (other.y - y) * t,
            z + (other.z - z) * t
        )
    }
}

private extension UIColor {
    func brightened(amount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(
            red: min(red * amount, 1),
            green: min(green * amount, 1),
            blue: min(blue * amount, 1),
            alpha: alpha
        )
    }

    func darker(amount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let scale = max(0, 1 - amount)
        return UIColor(red: red * scale, green: green * scale, blue: blue * scale, alpha: alpha)
    }
}
