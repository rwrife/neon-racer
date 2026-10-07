import Testing

#if !canImport(NeonRacerCore)
import SceneKit
import UIKit
@testable import NeonRacer

@MainActor
struct VehicleModels3DTests {
    @Test
    func raceUsesSelectedVehicleAndPaintMatchesTheCatalog() throws {
        for palette in ProgressionCatalog.palettes {
            let scene = RaceScene3D(garagePalette: palette, selectedVehicleID: "vector-sprint")
            let car = try #require(scene.scene.rootNode.childNode(
                withName: "hero-car-vector-sprint-\(palette.id)", recursively: true
            ))
            var paint: UIColor?
            car.enumerateChildNodes { node, _ in
                for material in node.geometry?.materials ?? [] where material.name == "vehicle-premium-clearcoat-paint" {
                    paint = material.diffuse.contents as? UIColor
                }
            }
            let color = try #require(paint)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            #expect(abs(red - CGFloat((palette.primaryHex >> 16) & 255) / 255) < 0.001)
            #expect(abs(green - CGFloat((palette.primaryHex >> 8) & 255) / 255) < 0.001)
            #expect(abs(blue - CGFloat(palette.primaryHex & 255) / 255) < 0.001)
        }
    }

    @Test
    func chaseCameraAlwaysStaysBehindAndLooksAlongTheRoad() {
        let camera = ChaseCamera3D()
        for heading in stride(from: Float(-4 * Double.pi), through: Float(4 * Double.pi), by: 0.12) {
            let frame = TrackWorldFrame3D(
                runDistance: 100, stageID: "test", distanceInStage: 100,
                position: SCNVector3(40, 3, -60), heading: heading, pitch: 0,
                roadHalfWidth: 6, shoulderWidth: 1, laneCount: 3, laneWidth: 4
            )
            camera.update(carFrame: frame, speedRatio: 1, isBoosting: true,
                          steering: 0.8, deltaTime: 1.0 / 60, time: 0)
            let offset = camera.currentPosition - frame.position
            #expect(offset.x * frame.forward.x + offset.z * frame.forward.z < -5)
            let facing = camera.cameraNode.convertVector(SCNVector3(0, 0, -1), to: nil)
            #expect(facing.x * frame.forward.x + facing.z * frame.forward.z > 0.9)
        }
    }

    @Test
    func heroFactoryBuildsReadableRetroWedgeWithAnimatedParts() {
        let car = VehicleModels3D.makeHeroCar(vehicleID: "prototype-zero", paletteID: "synthwave")

        #expect(car.name == "hero-car-prototype-zero-synthwave")
        #expect(car.childNode(withName: "hero-wedge-body", recursively: true) != nil)
        #expect(car.childNode(withName: "hero-full-width-taillight-bar", recursively: true) != nil)
        #expect(car.childNode(withName: "hero-smoked-taillight-lens-cover", recursively: true) != nil)
        #expect(car.childNode(withName: "hero-segmented-rear-light-core", recursively: true) != nil)
        #expect(car.childNode(withName: "hero-chrome-rear-trim", recursively: true) != nil)
        #expect(car.childNode(withName: "hero-chunky-rear-wheel-glowing-rim-ring", recursively: true) != nil)
        #expect(car.childNode(withName: "boost-exhaust-flame", recursively: true) != nil)

        let size = dimensions(of: car)
        #expect(size.x > 1.8 && size.x < 3.3)
        #expect(size.y > 1.0 && size.y < 1.8)
        #expect(size.z > 4.2 && size.z < 5.4)
    }

    @Test
    func trafficFactoriesKeepDistinctShapeCues() {
        let commuter = VehicleModels3D.makeTrafficVehicle(kind: .commuter, seed: 1)
        let hauler = VehicleModels3D.makeTrafficVehicle(kind: .hauler, seed: 2)
        let rival = VehicleModels3D.makeTrafficVehicle(kind: .rival, seed: 3)

        #expect(commuter.childNode(withName: "traffic-commuter-roof-accessibility-fin", recursively: true) != nil)
        #expect(hauler.childNode(withName: "traffic-hauler-long-cargo-container", recursively: true) != nil)
        #expect(rival.childNode(withName: "traffic-rival-left-chevron-taillight", recursively: true) != nil)
        #expect(dimensions(of: hauler).z > dimensions(of: commuter).z)
        #expect(dimensions(of: rival).x > dimensions(of: commuter).x)
    }

    @Test
    func obstacleFactoriesDocumentExpectedFootprintsWithNamesAndGeometry() {
        let barrier = VehicleModels3D.makeObstacle(kind: .neonBarrier)
        let pylons = VehicleModels3D.makeObstacle(kind: .pylon)
        let gate = VehicleModels3D.makeObstacle(kind: .laserGate)
        let billboard = VehicleModels3D.makeObstacle(kind: .roadsideBillboardPost)
        let palm = VehicleModels3D.makeObstacle(kind: .neonPalmTrunk)
        let holoSign = VehicleModels3D.makeObstacle(kind: .holoSignPylon)
        let debris = VehicleModels3D.makeObstacle(kind: .debris)

        #expect(barrier.name == "track-obstacle-neonBarrier-width-4m")
        #expect(pylons.name == "track-obstacle-pylon-width-1_5m")
        #expect(gate.name == "track-obstacle-laserGate-width-4m")
        #expect(billboard.name == "track-obstacle-roadsideBillboardPost-roadside-billboard-width-3m")
        #expect(palm.name == "track-obstacle-neonPalmTrunk-neon-palm-debris-width-2m")
        #expect(holoSign.name == "track-obstacle-holoSignPylon-holo-sign-pylons-width-2m")
        #expect(debris.name == "track-obstacle-debris-neon-palm-debris-width-2m")
        #expect(dimensions(of: barrier).x > 3.8 && dimensions(of: barrier).x < 4.3)
        #expect(dimensions(of: pylons).x > 1.1 && dimensions(of: pylons).x < 1.7)
        #expect(dimensions(of: gate).x > 3.9 && dimensions(of: gate).x < 4.5)
        #expect(dimensions(of: billboard).x > 2.8 && dimensions(of: billboard).x < 3.5)
        #expect(dimensions(of: palm).x > 1.4 && dimensions(of: palm).x < 2.4)
        #expect(dimensions(of: holoSign).x > 1.6 && dimensions(of: holoSign).x < 2.3)
        #expect(dimensions(of: debris).x > 1.4 && dimensions(of: debris).x < 2.4)
    }

    private func dimensions(of node: SCNNode) -> SCNVector3 {
        var minimum = SCNVector3Zero
        var maximum = SCNVector3Zero
        node.getBoundingBoxMin(&minimum, max: &maximum)
        return SCNVector3(
            maximum.x - minimum.x,
            maximum.y - minimum.y,
            maximum.z - minimum.z
        )
    }
}
#endif
