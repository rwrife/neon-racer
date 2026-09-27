import Testing

#if !canImport(NeonRacerCore)
@testable import NeonRacer

struct VehicleArtTests {
    @Test
    func vehicleClassesHaveUniqueSilhouettesAndValidConventions() {
        let definitions = VehicleArtCatalog.definitions

        #expect(definitions.count == VehicleClass.allCases.count)
        #expect(Set(definitions.map(\.vehicleClass)).count == definitions.count)
        #expect(Set(definitions.map { $0.body.count }).count > 1)
        #expect(definitions.allSatisfy { $0.canvasSize == VehicleArtCatalog.nativeCanvasSize })
        #expect(definitions.allSatisfy { (0...1).contains($0.anchor.x) })
        #expect(definitions.allSatisfy { (0...1).contains($0.anchor.y) })
        #expect(definitions.allSatisfy { $0.collisionBounds.minX >= 0 && $0.collisionBounds.maxX <= 1 })
        #expect(definitions.allSatisfy { $0.collisionBounds.minY >= 0 && $0.collisionBounds.maxY <= 1 })
    }

    @Test
    func frameSelectionUsesStableThresholdsAndPriority() {
        var selector = VehicleFrameSelector()

        #expect(selector.select(input: input(steering: -0.5), deltaTime: 0).state == .steerLeft)
        #expect(selector.select(input: input(steering: -0.18), deltaTime: 0.01).state == .steerLeft)
        #expect(selector.select(input: input(steering: -0.1), deltaTime: 0.01).state == .idle)
        #expect(selector.select(input: input(steering: 0.8, drift: 0.7), deltaTime: 0.01).state == .driftRight)
        #expect(selector.select(input: input(brake: 1, boost: true), deltaTime: 0.01).state == .boost)
        #expect(selector.select(input: input(boost: true, damage: 1), deltaTime: 0.01).state == .damage)
    }

    @Test
    func exportedFrameNamesAreDeterministic() {
        let names = VehicleMotionState.allCases.map {
            VehicleFrame(state: $0, phase: 0).atlasName
        }

        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.hasPrefix("vehicle.player-wedge.") && $0.hasSuffix(".00") })
    }

    private func input(
        steering: Double = 0,
        drift: Double = 0,
        brake: Double = 0,
        boost: Bool = false,
        damage: Double = 0
    ) -> VehicleVisualInput {
        VehicleVisualInput(
            steering: steering,
            drift: drift,
            brake: brake,
            boost: boost,
            damage: damage
        )
    }
}
#endif
