import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct InitialRouteContentTests {
    @Test
    func splitOffersThreeAndTwoLanesAndRejoinsBeforeTheNextCheckpoint() throws {
        let layout = TrackLayout.initialContent()
        let split = try #require(layout.split(for: "coast-solar-sweep"))
        #expect(split.narrowLaneCount == 2)
        #expect(split.mergeEnd < layout.profile(for: "coast-solar-sweep").length)
        let middle = split.crossSection(at: 500, laneWidth: 4)
        #expect(middle.leftHalfWidth == 6)
        #expect(middle.rightHalfWidth == 4)
        #expect(middle.laneCenters.count == 5)
        let sample = layout.sample(stageID: "coast-solar-sweep", distanceInStage: 500)
        #expect(sample.isOffRoad(lateralPosition: 0))
        #expect(!sample.isOffRoad(lateralPosition: middle.leftCenter / middle.roadHalfWidth))
        #expect(!sample.isOffRoad(lateralPosition: middle.rightCenter / middle.roadHalfWidth))
        for center in middle.laneCenters { #expect(!sample.isOffRoad(lateralPosition: center)) }
        for boundary in [split.entrance, split.entrance + split.transitionLength, split.mergeStart, split.mergeEnd] {
            let before = layout.sample(stageID: "coast-solar-sweep", distanceInStage: boundary - 0.001)
            let after = layout.sample(stageID: "coast-solar-sweep", distanceInStage: boundary + 0.001)
            #expect(abs(after.roadHalfWidth - before.roadHalfWidth) < 0.001)
        }
        let merged = layout.sample(stageID: "coast-solar-sweep", distanceInStage: split.mergeEnd + 1)
        #expect(merged.laneCount == 3)
        #expect(merged.roadHalfWidth == 6)
        #expect(!merged.isOffRoad(lateralPosition: 0))
    }

    @Test
    func skylineSplitHasASingleLaneAlternative() throws {
        let graph = ProgressionCatalog.routeGraph(id: "skyline-run", configuration: .standard)
        let layout = TrackLayout.forRoute(graph)
        let split = try #require(layout.split(for: "skyline-1"))
        let cross = split.crossSection(at: split.entrance + split.transitionLength + 1, laneWidth: 4)
        #expect(split.narrowLaneCount == 1)
        #expect(cross.rightHalfWidth == 2)
        #expect(cross.laneCenters.count == 4)
    }

    @Test
    func tunnelCameraEnvelopeLowersBeforeEntranceAndRestoresAfterExit() throws {
        let layout = TrackLayout.initialContent()
        let tunnel = try #require(layout.tunnel(for: "city-axis-tunnel"))
        #expect(tunnel.entrance == 120)
        #expect(tunnel.exit == 600)
        #expect(tunnel.cameraBlend(at: 60) == 0)
        #expect(tunnel.cameraBlend(at: 90) == 0.5)
        #expect(tunnel.cameraBlend(at: 120) == 1)
        #expect(tunnel.cameraBlend(at: 624) == 1)
        #expect(tunnel.cameraBlend(at: 684) == 0)
        #expect(layout.tunnel(for: "coast-causeway") == nil)
        for edge in [60.0, 120, 624, 684] {
            #expect(abs(tunnel.cameraBlend(at: edge - 0.01) - tunnel.cameraBlend(at: edge + 0.01)) < 0.001)
        }
        #expect(tunnel.contains(300))
        #expect(!tunnel.contains(90))
    }

    @Test
    func authoredBundlePassesValidation() {
        #expect(InitialRouteContent.bundle.validationDiagnostics.isEmpty)
    }

    @Test
    func everyForkPathVisitsAllThreeThemesAndFinishes() {
        let bundle = InitialRouteContent.bundle
        let route = bundle.document.stage.route
        let paths = bundle.completePaths()

        #expect(paths.count == 2)
        for path in paths {
            #expect(path.first == route.startSectionID)
            #expect(path.last == route.finishSectionIDs.first)
            #expect(Set(path.compactMap(bundle.themeID(for:))) == [
                "sunset-coast",
                "neon-city",
                "midnight-peaks"
            ])
        }
        #expect(bundle.hasReconnectAfterFork)
    }

    @Test
    func stageRoadMetadataMatchesOrderedGeometry() {
        let bundle = InitialRouteContent.bundle
        let sections = bundle.document.stage.route.sections
        for zone in bundle.themeZones {
            let length = sections
                .filter { zone.sectionIDs.contains($0.id) }
                .reduce(0) { $0 + $1.length }
            #expect(length >= 1_800)
        }
    }

    @Test
    func contentRoundTripsThroughCodableWithoutLoss() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(InitialRouteContent.bundle)
        let decoded = try JSONDecoder().decode(InitialRouteContentBundle.self, from: data)

        #expect(decoded == InitialRouteContent.bundle)
        #expect(decoded.validationDiagnostics.isEmpty)
    }

    @Test
    func allSceneryIsOriginalProceduralPlaceholderContent() {
        let bundle = InitialRouteContent.bundle
        let assets = bundle.document.assets.entries

        #expect(!assets.isEmpty)
        #expect(assets.allSatisfy { $0.resourceName.hasPrefix("procedural://") })
        #expect(Set(assets.map(\.id)) == Set(bundle.proceduralPlaceholders.map(\.assetID)))
    }

    @Test
    func validationRejectsTransitionThatIsNotARouteLink() {
        let valid = InitialRouteContent.bundle
        let invalid = InitialRouteContentBundle(
            document: valid.document,
            themeZones: valid.themeZones,
            transitions: [
                ThemeTransitionDefinition(
                    id: "broken-transition",
                    fromSectionID: "coast-causeway",
                    toSectionID: "peaks-summit-finish",
                    length: 200,
                    paletteBlendSeconds: 2,
                    sceneryCrossfadeSeconds: 2,
                    musicCrossfadeSeconds: 2,
                    preloadDistance: 500
                )
            ],
            proceduralPlaceholders: valid.proceduralPlaceholders
        )

        #expect(invalid.validationDiagnostics.contains {
            $0.code == "transition.unlinked"
        })
    }
}
