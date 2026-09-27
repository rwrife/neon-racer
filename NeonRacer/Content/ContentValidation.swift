import Foundation

struct ContentDiagnostic: Error, Equatable, Sendable, CustomStringConvertible {
    enum Severity: String, Equatable, Sendable {
        case error
        case warning
    }

    let source: String
    let field: String
    let code: String
    let severity: Severity
    let message: String

    var description: String {
        "\(source): \(severity.rawValue) [\(code)] at \(field): \(message)"
    }
}

protocol ContentAssetResolving {
    func contains(resourceNamed name: String, kind: AssetKind) -> Bool
}

struct BundleAssetResolver: ContentAssetResolving {
    let bundle: Bundle

    func contains(resourceNamed name: String, kind: AssetKind) -> Bool {
        let resource = name as NSString
        let extensionName = resource.pathExtension
        let baseName = resource.deletingPathExtension
        return bundle.url(
            forResource: baseName,
            withExtension: extensionName.isEmpty ? nil : extensionName
        ) != nil
    }
}

struct StageContentValidator {
    let assetResolver: (any ContentAssetResolving)?

    init(assetResolver: (any ContentAssetResolving)? = nil) {
        self.assetResolver = assetResolver
    }

    func validate(_ document: StageContentDocument, source: String) -> [ContentDiagnostic] {
        var diagnostics: [ContentDiagnostic] = []
        func report(_ field: String, _ code: String, _ message: String) {
            diagnostics.append(ContentDiagnostic(
                source: source,
                field: field,
                code: code,
                severity: .error,
                message: message
            ))
        }

        if document.schemaVersion != StageContentDocument.currentSchemaVersion {
            report("schemaVersion", "schema.unsupported", "Expected schema version \(StageContentDocument.currentSchemaVersion), found \(document.schemaVersion).")
        }

        validateID(document.stage.id, field: "stage.id", report: report)
        validateUnique(document.palettes, at: "palettes", report: report)
        validateUnique(document.trafficProfiles, at: "trafficProfiles", report: report)
        validateUnique(document.sceneryProfiles, at: "sceneryProfiles", report: report)
        validateUnique(document.weatherProfiles, at: "weatherProfiles", report: report)
        validateUnique(document.musicCues, at: "musicCues", report: report)
        validateUnique(document.difficulties, at: "difficulties", report: report)
        validateUnique(document.assets.entries, at: "assets.entries", report: report)

        validateReference(document.stage.paletteID, in: document.palettes, field: "stage.paletteID", report: report)
        validateReference(document.stage.trafficProfileID, in: document.trafficProfiles, field: "stage.trafficProfileID", report: report)
        validateReference(document.stage.sceneryProfileID, in: document.sceneryProfiles, field: "stage.sceneryProfileID", report: report)
        validateReference(document.stage.weatherProfileID, in: document.weatherProfiles, field: "stage.weatherProfileID", report: report)
        for (index, id) in document.stage.musicCueIDs.enumerated() {
            validateReference(id, in: document.musicCues, field: "stage.musicCueIDs[\(index)]", report: report)
        }
        for (index, id) in document.stage.difficultyIDs.enumerated() {
            validateReference(id, in: document.difficulties, field: "stage.difficultyIDs[\(index)]", report: report)
        }

        validateRoute(document.stage.route, budgets: document.budgets, report: report)
        validatePalettes(document.palettes, report: report)
        validateTraffic(document.trafficProfiles, assets: document.assets, budgets: document.budgets, report: report)
        validateScenery(document.sceneryProfiles, assets: document.assets, budgets: document.budgets, report: report)
        validateWeather(document.weatherProfiles, assets: document.assets, report: report)
        validateMusic(document.musicCues, assets: document.assets, report: report)
        validateDifficulty(document.difficulties, report: report)
        validateAssets(document.assets, report: report)
        validateBudgets(document.budgets, report: report)
        return diagnostics
    }

    private func validateRoute(
        _ route: RouteGraphDefinition,
        budgets: ContentBudget,
        report: (String, String, String) -> Void
    ) {
        validateUnique(route.sections, at: "stage.route.sections", report: report)
        validateUnique(route.checkpoints, at: "stage.route.checkpoints", report: report)
        validateUnique(route.forks, at: "stage.route.forks", report: report)

        let sectionIDs = Set(route.sections.map(\.id))
        let forkIDs = Set(route.forks.map(\.id))
        if !sectionIDs.contains(route.startSectionID) {
            report("stage.route.startSectionID", "route.missing-start", "No section has ID '\(route.startSectionID)'.")
        }
        if route.finishSectionIDs.isEmpty {
            report("stage.route.finishSectionIDs", "route.missing-finish", "At least one finish section is required.")
        }
        for (index, id) in route.finishSectionIDs.enumerated() where !sectionIDs.contains(id) {
            report("stage.route.finishSectionIDs[\(index)]", "route.missing-link", "No section has ID '\(id)'.")
        }

        for (index, section) in route.sections.enumerated() {
            let path = "stage.route.sections[\(index)]"
            validateID(section.id, field: "\(path).id", report: report)
            positive(section.length, field: "\(path).length", report: report)
            for (name, value) in [("entry", section.curve.entry), ("apex", section.curve.apex), ("exit", section.curve.exit)] {
                bounded(value, range: -1...1, field: "\(path).curve.\(name)", report: report)
            }
            finite(section.elevation.startMeters, field: "\(path).elevation.startMeters", report: report)
            finite(section.elevation.endMeters, field: "\(path).elevation.endMeters", report: report)
            if let crest = section.elevation.crestMeters {
                finite(crest, field: "\(path).elevation.crestMeters", report: report)
            }
            if !(1...8).contains(section.lanes.count) {
                report("\(path).lanes.count", "range.lanes", "Lane count must be between 1 and 8.")
            }
            bounded(section.lanes.width, range: 2.5...6, field: "\(path).lanes.width", report: report)
            bounded(section.lanes.shoulderWidth, range: 0...5, field: "\(path).lanes.shoulderWidth", report: report)
            validateUnique(section.laneChanges, at: "\(path).laneChanges", report: report)
            var previousPosition = -Double.infinity
            for (changeIndex, change) in section.laneChanges.enumerated() {
                let changePath = "\(path).laneChanges[\(changeIndex)]"
                bounded(change.at, range: 0...section.length, field: "\(changePath).at", report: report)
                if change.at <= previousPosition {
                    report("\(changePath).at", "ordering.lane-change", "Lane changes must be strictly ordered by position.")
                }
                previousPosition = change.at
                if !(1...8).contains(change.laneCount) {
                    report("\(changePath).laneCount", "range.lanes", "Lane count must be between 1 and 8.")
                }
            }
            for (linkIndex, link) in section.links.enumerated() {
                let linkPath = "\(path).links[\(linkIndex)]"
                if !sectionIDs.contains(link.destinationSectionID) {
                    report("\(linkPath).destinationSectionID", "route.missing-link", "No section has ID '\(link.destinationSectionID)'.")
                }
                if let forkID = link.forkID, !forkIDs.contains(forkID) {
                    report("\(linkPath).forkID", "route.missing-fork", "No fork has ID '\(forkID)'.")
                }
            }
        }

        var previousOrder = -1
        var seenOrders = Set<Int>()
        for (index, checkpoint) in route.checkpoints.enumerated() {
            let path = "stage.route.checkpoints[\(index)]"
            validateID(checkpoint.id, field: "\(path).id", report: report)
            guard let section = route.sections.first(where: { $0.id == checkpoint.sectionID }) else {
                report("\(path).sectionID", "route.missing-link", "No section has ID '\(checkpoint.sectionID)'.")
                continue
            }
            bounded(checkpoint.at, range: 0...section.length, field: "\(path).at", report: report)
            if checkpoint.order < 0 || !seenOrders.insert(checkpoint.order).inserted {
                report("\(path).order", "ordering.checkpoint", "Checkpoint order must be unique and nonnegative.")
            }
            if checkpoint.order <= previousOrder {
                report("\(path).order", "ordering.checkpoint", "Checkpoints must be listed in strictly increasing order.")
            }
            previousOrder = checkpoint.order
        }

        for (index, fork) in route.forks.enumerated() {
            let path = "stage.route.forks[\(index)]"
            validateID(fork.id, field: "\(path).id", report: report)
            guard let source = route.sections.first(where: { $0.id == fork.sectionID }) else {
                report("\(path).sectionID", "route.missing-link", "No section has ID '\(fork.sectionID)'.")
                continue
            }
            bounded(fork.at, range: 0...source.length, field: "\(path).at", report: report)
            if fork.destinationSectionIDs.count < 2 {
                report("\(path).destinationSectionIDs", "route.invalid-fork", "A fork requires at least two destinations.")
            }
            let linkedDestinations = Set(source.links.filter { $0.forkID == fork.id }.map(\.destinationSectionID))
            for (destinationIndex, destination) in fork.destinationSectionIDs.enumerated() {
                if !sectionIDs.contains(destination) {
                    report("\(path).destinationSectionIDs[\(destinationIndex)]", "route.missing-link", "No section has ID '\(destination)'.")
                } else if !linkedDestinations.contains(destination) {
                    report("\(path).destinationSectionIDs[\(destinationIndex)]", "route.unlinked-fork", "Section '\(fork.sectionID)' has no matching link for this fork destination.")
                }
            }
            if !fork.destinationSectionIDs.contains(fork.defaultDestinationSectionID) {
                report("\(path).defaultDestinationSectionID", "route.invalid-fork", "Default destination must be one of destinationSectionIDs.")
            }
        }

        var adjacency: [String: [String]] = [:]
        for section in route.sections where adjacency[section.id] == nil {
            adjacency[section.id] = section.links.map(\.destinationSectionID)
        }
        let reachable = reachableIDs(from: route.startSectionID, adjacency: adjacency)
        for (index, section) in route.sections.enumerated() where !reachable.contains(section.id) {
            report("stage.route.sections[\(index)].id", "route.unreachable", "Section '\(section.id)' is not reachable from the start.")
        }
        if !route.finishSectionIDs.contains(where: reachable.contains) {
            report("stage.route.finishSectionIDs", "route.unreachable-finish", "No finish is reachable from the start.")
        }
        let reverse = reverseAdjacency(adjacency)
        let canReachFinish = route.finishSectionIDs.reduce(into: Set<String>()) {
            $0.formUnion(reachableIDs(from: $1, adjacency: reverse))
        }
        for (index, fork) in route.forks.enumerated() {
            for (destinationIndex, destination) in fork.destinationSectionIDs.enumerated()
            where !canReachFinish.contains(destination) {
                report("stage.route.forks[\(index)].destinationSectionIDs[\(destinationIndex)]", "route.dead-end", "Destination '\(destination)' cannot reach a finish.")
            }
        }

        if route.sections.count > budgets.maximumSections {
            report("stage.route.sections", "budget.sections", "\(route.sections.count) sections exceed the budget of \(budgets.maximumSections).")
        }
        let totalLength = route.sections.reduce(0) { $0 + $1.length }
        if totalLength > budgets.maximumTotalRoadLength {
            report("stage.route.sections", "budget.road-length", "Total road length \(totalLength) exceeds the budget of \(budgets.maximumTotalRoadLength).")
        }
    }

    private func validatePalettes(_ palettes: [PaletteDefinition], report: (String, String, String) -> Void) {
        for (index, palette) in palettes.enumerated() {
            validateID(palette.id, field: "palettes[\(index)].id", report: report)
            let colors = [
                ("skyTopHex", palette.skyTopHex),
                ("skyBottomHex", palette.skyBottomHex),
                ("roadHex", palette.roadHex),
                ("shoulderHex", palette.shoulderHex),
                ("laneMarkerHex", palette.laneMarkerHex),
                ("primaryAccentHex", palette.primaryAccentHex),
                ("secondaryAccentHex", palette.secondaryAccentHex),
                ("fogHex", palette.fogHex)
            ]
            for (field, color) in colors
            where color.range(of: "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$", options: .regularExpression) == nil {
                report("palettes[\(index)].\(field)", "format.color", "'\(color)' must be #RRGGBB or #RRGGBBAA.")
            }
        }
    }

    private func validateTraffic(
        _ profiles: [TrafficProfileDefinition],
        assets: AssetManifest,
        budgets: ContentBudget,
        report: (String, String, String) -> Void
    ) {
        for (index, profile) in profiles.enumerated() {
            let path = "trafficProfiles[\(index)]"
            validateID(profile.id, field: "\(path).id", report: report)
            bounded(profile.baseDensity, range: 0...1, field: "\(path).baseDensity", report: report)
            positive(profile.minimumHeadway, field: "\(path).minimumHeadway", report: report)
            ordered(profile.speedRange, field: "\(path).speedRange", report: report)
            positive(profile.speedRange.lowerBound, field: "\(path).speedRange.lowerBound", report: report)
            if profile.vehicleAssetIDs.isEmpty {
                report("\(path).vehicleAssetIDs", "asset.empty-list", "At least one vehicle asset is required.")
            }
            if profile.maximumVehicles < 0 || profile.maximumVehicles > budgets.maximumTrafficVehicles {
                report("\(path).maximumVehicles", "budget.traffic", "Must be between 0 and the traffic budget of \(budgets.maximumTrafficVehicles).")
            }
            for (assetIndex, id) in profile.vehicleAssetIDs.enumerated() {
                validateAssetReference(id, kind: .vehicle, assets: assets, field: "\(path).vehicleAssetIDs[\(assetIndex)]", report: report)
            }
        }
    }

    private func validateScenery(
        _ profiles: [SceneryProfileDefinition],
        assets: AssetManifest,
        budgets: ContentBudget,
        report: (String, String, String) -> Void
    ) {
        for (index, profile) in profiles.enumerated() {
            let path = "sceneryProfiles[\(index)]"
            validateID(profile.id, field: "\(path).id", report: report)
            validateUnique(profile.bands, at: "\(path).bands", report: report)
            let instances = profile.bands.reduce(0) { $0 + $1.maximumInstances }
            if instances > budgets.maximumSceneryInstances {
                report("\(path).bands", "budget.scenery", "\(instances) scenery instances exceed the budget of \(budgets.maximumSceneryInstances).")
            }
            for (bandIndex, band) in profile.bands.enumerated() {
                let bandPath = "\(path).bands[\(bandIndex)]"
                validateID(band.id, field: "\(bandPath).id", report: report)
                ordered(band.distanceRange, field: "\(bandPath).distanceRange", report: report)
                ordered(band.lateralRange, field: "\(bandPath).lateralRange", report: report)
                nonnegative(band.distanceRange.lowerBound, field: "\(bandPath).distanceRange.lowerBound", report: report)
                positive(band.spacing, field: "\(bandPath).spacing", report: report)
                if band.maximumInstances < 0 {
                    report("\(bandPath).maximumInstances", "range.negative", "Must be nonnegative.")
                }
                if band.assetIDs.isEmpty {
                    report("\(bandPath).assetIDs", "asset.empty-list", "At least one scenery asset is required.")
                }
                for (assetIndex, id) in band.assetIDs.enumerated() {
                    validateAssetReference(id, kind: .image, assets: assets, field: "\(bandPath).assetIDs[\(assetIndex)]", report: report)
                }
            }
        }
    }

    private func validateWeather(
        _ profiles: [WeatherDefinition],
        assets: AssetManifest,
        report: (String, String, String) -> Void
    ) {
        for (index, weather) in profiles.enumerated() {
            let path = "weatherProfiles[\(index)]"
            validateID(weather.id, field: "\(path).id", report: report)
            bounded(weather.intensity, range: 0...1, field: "\(path).intensity", report: report)
            bounded(weather.visibility, range: 0...1, field: "\(path).visibility", report: report)
            bounded(weather.roadGrip, range: 0...2, field: "\(path).roadGrip", report: report)
            if let id = weather.particleAssetID {
                validateAssetReference(id, kind: .particle, assets: assets, field: "\(path).particleAssetID", report: report)
            }
        }
    }

    private func validateMusic(
        _ cues: [MusicCueDefinition],
        assets: AssetManifest,
        report: (String, String, String) -> Void
    ) {
        for (index, cue) in cues.enumerated() {
            let path = "musicCues[\(index)]"
            validateID(cue.id, field: "\(path).id", report: report)
            nonnegative(cue.crossfadeSeconds, field: "\(path).crossfadeSeconds", report: report)
            validateAssetReference(cue.assetID, kind: .audio, assets: assets, field: "\(path).assetID", report: report)
        }
    }

    private func validateDifficulty(_ definitions: [DifficultyDefinition], report: (String, String, String) -> Void) {
        for (index, difficulty) in definitions.enumerated() {
            let path = "difficulties[\(index)]"
            validateID(difficulty.id, field: "\(path).id", report: report)
            positive(difficulty.trafficDensityMultiplier, field: "\(path).trafficDensityMultiplier", report: report)
            positive(difficulty.opponentSpeedMultiplier, field: "\(path).opponentSpeedMultiplier", report: report)
            positive(difficulty.timeLimitSeconds, field: "\(path).timeLimitSeconds", report: report)
            nonnegative(difficulty.checkpointTimeBonusSeconds, field: "\(path).checkpointTimeBonusSeconds", report: report)
            positive(difficulty.scoreMultiplier, field: "\(path).scoreMultiplier", report: report)
        }
    }

    private func validateAssets(_ manifest: AssetManifest, report: (String, String, String) -> Void) {
        for (index, asset) in manifest.entries.enumerated() {
            let path = "assets.entries[\(index)]"
            validateID(asset.id, field: "\(path).id", report: report)
            if asset.resourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                report("\(path).resourceName", "asset.empty", "Resource name must not be empty.")
            } else if let assetResolver, !assetResolver.contains(resourceNamed: asset.resourceName, kind: asset.kind) {
                report("\(path).resourceName", "asset.missing-resource", "Bundle resource '\(asset.resourceName)' was not found.")
            }
        }
    }

    private func validateBudgets(_ budgets: ContentBudget, report: (String, String, String) -> Void) {
        if budgets.maximumSections <= 0 { report("budgets.maximumSections", "budget.invalid", "Must be greater than zero.") }
        positive(budgets.maximumTotalRoadLength, field: "budgets.maximumTotalRoadLength", report: report)
        if budgets.maximumSceneryInstances < 0 { report("budgets.maximumSceneryInstances", "budget.invalid", "Must be nonnegative.") }
        if budgets.maximumTrafficVehicles < 0 { report("budgets.maximumTrafficVehicles", "budget.invalid", "Must be nonnegative.") }
        let hardLimit = ContentBudget.recommended
        if budgets.maximumSections > hardLimit.maximumSections {
            report("budgets.maximumSections", "budget.hard-limit", "Cannot exceed the engine limit of \(hardLimit.maximumSections).")
        }
        if budgets.maximumTotalRoadLength > hardLimit.maximumTotalRoadLength {
            report("budgets.maximumTotalRoadLength", "budget.hard-limit", "Cannot exceed the engine limit of \(hardLimit.maximumTotalRoadLength).")
        }
        if budgets.maximumSceneryInstances > hardLimit.maximumSceneryInstances {
            report("budgets.maximumSceneryInstances", "budget.hard-limit", "Cannot exceed the engine limit of \(hardLimit.maximumSceneryInstances).")
        }
        if budgets.maximumTrafficVehicles > hardLimit.maximumTrafficVehicles {
            report("budgets.maximumTrafficVehicles", "budget.hard-limit", "Cannot exceed the engine limit of \(hardLimit.maximumTrafficVehicles).")
        }
    }

    private func validateAssetReference(
        _ id: String,
        kind: AssetKind,
        assets: AssetManifest,
        field: String,
        report: (String, String, String) -> Void
    ) {
        guard let asset = assets.entries.first(where: { $0.id == id }) else {
            report(field, "asset.unknown", "No asset has ID '\(id)'.")
            return
        }
        if asset.kind != kind {
            report(field, "asset.kind", "Asset '\(id)' is \(asset.kind.rawValue), expected \(kind.rawValue).")
        }
    }

    private func validateReference<T: ContentIdentifiable>(
        _ id: String,
        in values: [T],
        field: String,
        report: (String, String, String) -> Void
    ) {
        if !values.contains(where: { $0.id == id }) {
            report(field, "reference.unknown", "No definition has ID '\(id)'.")
        }
    }

    private func validateUnique<T: ContentIdentifiable>(
        _ values: [T],
        at field: String,
        report: (String, String, String) -> Void
    ) {
        var seen = Set<String>()
        for (index, value) in values.enumerated() {
            if !seen.insert(value.id).inserted {
                report("\(field)[\(index)].id", "id.duplicate", "ID '\(value.id)' is duplicated in \(field).")
            }
        }
    }

    private func validateID(_ id: String, field: String, report: (String, String, String) -> Void) {
        if id.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) == nil {
            report(field, "id.invalid", "'\(id)' must use lowercase letters, digits, and hyphens, beginning with a letter.")
        }
    }

    private func finite(_ value: Double, field: String, report: (String, String, String) -> Void) {
        if !value.isFinite { report(field, "range.nonfinite", "Must be finite.") }
    }

    private func positive(_ value: Double, field: String, report: (String, String, String) -> Void) {
        if !value.isFinite || value <= 0 { report(field, "range.positive", "Must be finite and greater than zero.") }
    }

    private func nonnegative(_ value: Double, field: String, report: (String, String, String) -> Void) {
        if !value.isFinite || value < 0 { report(field, "range.negative", "Must be finite and nonnegative.") }
    }

    private func bounded(
        _ value: Double,
        range: ClosedRange<Double>,
        field: String,
        report: (String, String, String) -> Void
    ) {
        if !value.isFinite || !range.contains(value) {
            report(field, "range.out-of-bounds", "Must be between \(range.lowerBound) and \(range.upperBound).")
        }
    }

    private func ordered(
        _ range: ClosedRangeValue<Double>,
        field: String,
        report: (String, String, String) -> Void
    ) {
        if !range.lowerBound.isFinite || !range.upperBound.isFinite || range.lowerBound > range.upperBound {
            report(field, "range.unordered", "Bounds must be finite and lowerBound must not exceed upperBound.")
        }
    }

    private func reachableIDs(from start: String, adjacency: [String: [String]]) -> Set<String> {
        var visited = Set<String>()
        var pending = [start]
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else { continue }
            pending.append(contentsOf: adjacency[current] ?? [])
        }
        return visited
    }

    private func reverseAdjacency(_ adjacency: [String: [String]]) -> [String: [String]] {
        var reversed: [String: [String]] = [:]
        for (source, destinations) in adjacency {
            reversed[source, default: []] = reversed[source, default: []]
            for destination in destinations {
                reversed[destination, default: []].append(source)
            }
        }
        return reversed
    }
}
