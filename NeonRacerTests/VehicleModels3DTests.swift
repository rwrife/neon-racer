import Testing

#if !canImport(NeonRacerCore)
import SceneKit
@testable import NeonRacer

@MainActor
struct VehicleModels3DTests {
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
