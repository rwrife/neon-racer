import Foundation
import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct InitialRouteContentTests {
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
