#if !canImport(NeonRacerCore)
import Foundation
import SceneKit
import Testing
import UIKit
@testable import NeonRacer

struct NeonEffects3DTests {
    @Test
    func accessibilityScalingSuppressesMotionAndFlashing() {
        let standard = NeonEffects3DScaling(quality: .fidelity, reduceMotion: false, reduceFlashing: false, globalIntensity: 1)
        let reducedMotion = NeonEffects3DScaling(quality: .fidelity, reduceMotion: true, reduceFlashing: false, globalIntensity: 1)
        let reducedFlash = NeonEffects3DScaling(quality: .fidelity, reduceMotion: false, reduceFlashing: true, globalIntensity: 1)

        #expect(reducedMotion.effectiveIntensity(for: .speedStreaks) < standard.effectiveIntensity(for: .speedStreaks))
        #expect(reducedMotion.effectiveIntensity(for: .chromaticSeparation) < standard.effectiveIntensity(for: .chromaticSeparation))
        #expect(reducedFlash.effectiveIntensity(for: .collisionFlash) == 0)
        #expect(reducedFlash.effectiveIntensity(for: .bloom) < standard.effectiveIntensity(for: .bloom))
    }

    @Test
    func qualityTiersScaleParticleEffectsMonotonically() {
        let effects: [NeonEffect] = [.speedStreaks, .boostTrails, .sparks, .tireSmoke, .exhaust]
        for effect in effects {
            let efficiency = NeonEffects3DScaling(quality: .efficiency, reduceMotion: false, reduceFlashing: false, globalIntensity: 1)
                .effectiveIntensity(for: effect)
            let balanced = NeonEffects3DScaling(quality: .balanced, reduceMotion: false, reduceFlashing: false, globalIntensity: 1)
                .effectiveIntensity(for: effect)
            let fidelity = NeonEffects3DScaling(quality: .fidelity, reduceMotion: false, reduceFlashing: false, globalIntensity: 1)
                .effectiveIntensity(for: effect)
            #expect(efficiency <= balanced)
            #expect(balanced <= fidelity)
        }
    }

    @Test @MainActor
    func checkpointLaunchesTwoFireworkBursts() throws {
        let effects = NeonEffects3D()
        effects.setPose(carPosition: SCNVector3(0, 0, 0), cameraForward: SCNVector3(0, 0, -1))
        effects.trigger(.checkpoint)

        let left = try #require(effects.rootNode.childNode(withName: "checkpoint-cyan-fireworks", recursively: false))
        let right = try #require(effects.rootNode.childNode(withName: "checkpoint-magenta-fireworks", recursively: false))
        let leftBurst = try #require(left.particleSystems?.first)
        let rightBurst = try #require(right.particleSystems?.first)
        #expect(leftBurst.birthRate > 0)
        #expect(rightBurst.birthRate > 0)
    }

    @Test @MainActor
    func crashEffectsExposeReadableCameraHintsAndWeatherNoOps() {
        let effects = NeonEffects3D()
        effects.setWeather("rain")
        effects.apply(reduceMotion: false, reduceFlashing: false, intensity: 1)
        effects.trigger(.crash)
        effects.update(speedRatio: 1, isBoosting: false, isDrifting: false, isOffRoad: false, time: 10)

        #expect(effects.fovKick > 0)
        #expect(effects.timeDilationHint < 1)

        effects.apply(reduceMotion: true, reduceFlashing: true, intensity: 1)
        effects.trigger(.collision(intensity: 1))
        effects.update(speedRatio: 1, isBoosting: false, isDrifting: false, isOffRoad: false, time: 10.1)

        #expect(effects.fovKick == 0)
        #expect(effects.timeDilationHint == 1)
        #expect(effects.cameraShakeOffset == SCNVector3Zero)
    }

    @Test @MainActor
    func writesSnapshotWhenRequested() throws {
        guard let directory = ProcessInfo.processInfo.environment["NEON_EFFECTS3D_SNAPSHOT_DIR"], !directory.isEmpty else {
            return
        }

        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.015, green: 0, blue: 0.05, alpha: 1)
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 3.2, 9)
        cameraNode.look(at: SCNVector3(0, 1, 0))
        scene.rootNode.addChildNode(cameraNode)

        let carNode = SCNNode(geometry: SCNBox(width: 1.9, height: 0.7, length: 4.2, chamferRadius: 0.08))
        carNode.geometry?.materials = [Self.material(.red)]
        carNode.position = SCNVector3(0, 0.45, 0)
        scene.rootNode.addChildNode(carNode)

        for index in -4...4 {
            let cyan = SCNNode(geometry: SCNCylinder(radius: 0.025, height: 28))
            cyan.geometry?.materials = [Self.material(.cyan)]
            cyan.eulerAngles.x = .pi / 2
            cyan.position = SCNVector3(Float(index) * 1.4, 0.02, -8)
            scene.rootNode.addChildNode(cyan)
        }

        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        view.scene = scene
        view.pointOfView = cameraNode
        let effects = NeonEffects3D()
        effects.configure(camera: camera)
        effects.install(on: view)
        effects.attach(to: scene, carNode: carNode, cameraNode: cameraNode)
        effects.apply(quality: .fidelity)
        effects.update(speedRatio: 1, isBoosting: true, isDrifting: true, isOffRoad: false, time: 1)
        effects.trigger(.boostStart)
        effects.trigger(.nearMiss)
        effects.update(speedRatio: 1, isBoosting: true, isDrifting: true, isOffRoad: false, time: 1.1)

        let image = view.snapshot()
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = "\(directory)/effects3d-\(Int(Date().timeIntervalSince1970)).png"
        try #require(image.pngData()).write(to: URL(fileURLWithPath: path))
    }

    private static func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.lightingModel = .constant
        return material
    }
}
#endif
