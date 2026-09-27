import Foundation

struct InitialRouteContentBundle: Codable, Equatable, Sendable {
    let document: StageContentDocument
    let themeZones: [ThemeZoneDefinition]
    let transitions: [ThemeTransitionDefinition]
    let proceduralPlaceholders: [ProceduralPlaceholderDefinition]

    var validationDiagnostics: [ContentDiagnostic] {
        var diagnostics = StageContentValidator().validate(
            document,
            source: "InitialRouteContent.bundle"
        )

        func report(_ field: String, _ code: String, _ message: String) {
            diagnostics.append(ContentDiagnostic(
                source: "InitialRouteContent.bundle",
                field: field,
                code: code,
                severity: .error,
                message: message
            ))
        }

        let sections = document.stage.route.sections
        let sectionIDs = Set(sections.map(\.id))
        let palettes = Set(document.palettes.map(\.id))
        let traffic = Set(document.trafficProfiles.map(\.id))
        let scenery = Set(document.sceneryProfiles.map(\.id))
        let weather = Set(document.weatherProfiles.map(\.id))
        let music = Set(document.musicCues.map(\.id))
        let zoneIDs = themeZones.map(\.id)

        if Set(zoneIDs).count != zoneIDs.count {
            report("themeZones", "id.duplicate", "Theme zone IDs must be unique.")
        }

        var assignedSections = Set<String>()
        for (index, zone) in themeZones.enumerated() {
            let field = "themeZones[\(index)]"
            if zone.sectionIDs.isEmpty {
                report("\(field).sectionIDs", "theme.empty", "A theme zone must contain road sections.")
            }
            for sectionID in zone.sectionIDs {
                if !sectionIDs.contains(sectionID) {
                    report("\(field).sectionIDs", "route.missing-link", "No section has ID '\(sectionID)'.")
                } else if !assignedSections.insert(sectionID).inserted {
                    report("\(field).sectionIDs", "theme.overlap", "Section '\(sectionID)' belongs to more than one theme zone.")
                }
            }
            for (id, values, name) in [
                (zone.paletteID, palettes, "paletteID"),
                (zone.trafficProfileID, traffic, "trafficProfileID"),
                (zone.sceneryProfileID, scenery, "sceneryProfileID"),
                (zone.weatherProfileID, weather, "weatherProfileID"),
                (zone.musicCueID, music, "musicCueID")
            ] where !values.contains(id) {
                report("\(field).\(name)", "reference.unknown", "No definition has ID '\(id)'.")
            }
        }

        if assignedSections != sectionIDs {
            report("themeZones", "theme.incomplete", "Every road section must belong to exactly one theme zone.")
        }

        let requiredThemes = Set(["sunset-coast", "neon-city", "midnight-peaks"])
        let paths = completePaths()
        if paths.isEmpty {
            report("document.stage.route", "route.no-complete-path", "The route has no complete path.")
        }
        for (index, path) in paths.enumerated() {
            let themes = Set(path.compactMap { themeID(for: $0) })
            if !requiredThemes.isSubset(of: themes) {
                report("document.stage.route.paths[\(index)]", "route.missing-theme", "Every complete path must visit all three launch themes.")
            }
        }

        if !hasReconnectAfterFork {
            report("document.stage.route.forks", "route.no-reconnect", "Fork branches must reconnect before the finish.")
        }

        let links = Set(sections.flatMap { section in
            section.links.map { RoutePair(from: section.id, to: $0.destinationSectionID) }
        })
        for (index, transition) in transitions.enumerated() {
            let field = "transitions[\(index)]"
            if !links.contains(RoutePair(from: transition.fromSectionID, to: transition.toSectionID)) {
                report(field, "transition.unlinked", "Transition must correspond to a route link.")
            }
            if transition.length <= 0
                || transition.paletteBlendSeconds <= 0
                || transition.sceneryCrossfadeSeconds <= 0
                || transition.musicCrossfadeSeconds <= 0
                || transition.preloadDistance <= transition.length {
                report(field, "transition.invalid", "Transition timing and preload distance must be positive and preload must exceed transition length.")
            }
        }

        let placeholderIDs = proceduralPlaceholders.map(\.assetID)
        if Set(placeholderIDs).count != placeholderIDs.count {
            report("proceduralPlaceholders", "id.duplicate", "Procedural placeholder asset IDs must be unique.")
        }
        let assetIDs = Set(document.assets.entries.map(\.id))
        if Set(placeholderIDs) != assetIDs
            || document.assets.entries.contains(where: { !$0.resourceName.hasPrefix("procedural://") }) {
            report("proceduralPlaceholders", "asset.nonprocedural", "Every manifest entry must have one original procedural placeholder and no external resource.")
        }

        for (index, profile) in document.trafficProfiles.enumerated()
            where profile.minimumHeadway < 1.25 || profile.baseDensity > 0.72 {
            report("document.trafficProfiles[\(index)]", "traffic.unsafe", "Traffic must retain safe headway and density margins.")
        }
        for (index, profile) in document.weatherProfiles.enumerated()
            where profile.visibility < 0.65 || profile.roadGrip < 0.75 {
            report("document.weatherProfiles[\(index)]", "weather.unsafe", "Weather must preserve visibility and controllable road grip.")
        }

        return diagnostics
    }

    func completePaths() -> [[String]] {
        let route = document.stage.route
        let byID = Dictionary(uniqueKeysWithValues: route.sections.map { ($0.id, $0) })

        func walk(_ sectionID: String, path: [String]) -> [[String]] {
            guard !path.contains(sectionID), let section = byID[sectionID] else { return [] }
            let nextPath = path + [sectionID]
            if route.finishSectionIDs.contains(sectionID) { return [nextPath] }
            return section.links.flatMap { walk($0.destinationSectionID, path: nextPath) }
        }

        return walk(route.startSectionID, path: [])
    }

    func themeID(for sectionID: String) -> String? {
        themeZones.first { $0.sectionIDs.contains(sectionID) }?.id
    }

    var hasReconnectAfterFork: Bool {
        let route = document.stage.route
        let adjacency = Dictionary(uniqueKeysWithValues: route.sections.map {
            ($0.id, $0.links.map(\.destinationSectionID))
        })

        func reachable(from start: String) -> Set<String> {
            var found = Set<String>()
            var pending = [start]
            while let current = pending.popLast(), found.insert(current).inserted {
                pending.append(contentsOf: adjacency[current] ?? [])
            }
            return found
        }

        return route.forks.contains { fork in
            let sets = fork.destinationSectionIDs.map(reachable)
            guard let first = sets.first else { return false }
            return !sets.dropFirst().reduce(first) { $0.intersection($1) }.isEmpty
        }
    }

    private struct RoutePair: Hashable {
        let from: String
        let to: String
    }
}

struct ThemeZoneDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let sectionIDs: [String]
    let paletteID: String
    let trafficProfileID: String
    let sceneryProfileID: String
    let weatherProfileID: String
    let musicCueID: String
    let silhouetteIdentity: String
}

struct ThemeTransitionDefinition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let fromSectionID: String
    let toSectionID: String
    let length: Double
    let paletteBlendSeconds: Double
    let sceneryCrossfadeSeconds: Double
    let musicCrossfadeSeconds: Double
    let preloadDistance: Double
}

struct ProceduralPlaceholderDefinition: Codable, Equatable, Sendable, Identifiable {
    enum Primitive: String, Codable, Sendable {
        case vehicleSilhouette
        case stripedSunDisc
        case angularCoast
        case palmFan
        case skylineBlock
        case fictionalSignPanel
        case overpassSpan
        case tunnelBay
        case wireframeMountain
        case starField
        case auroraRibbon
        case relayBeacon
        case proceduralMusic
    }

    let assetID: String
    let primitive: Primitive
    let paletteRole: String
    let animationCue: String?
    let fictionalLabel: String?

    var id: String { assetID }
}

enum InitialRouteContent {
    static let bundle = InitialRouteContentBundle(
        document: document,
        themeZones: themeZones,
        transitions: transitions,
        proceduralPlaceholders: placeholders
    )

    private static let document = StageContentDocument(
        schemaVersion: StageContentDocument.currentSchemaVersion,
        stage: StageDefinition(
            id: "solar-to-summit",
            displayName: "Solar to Summit",
            route: route,
            paletteID: "sunset-coast-palette",
            trafficProfileID: "sunset-coast-traffic",
            sceneryProfileID: "sunset-coast-scenery",
            weatherProfileID: "sunset-coast-weather",
            musicCueIDs: ["coastline-pulse", "vertical-current", "summit-signal"],
            difficultyIDs: ["solar-to-summit-standard"]
        ),
        palettes: palettes,
        trafficProfiles: trafficProfiles,
        sceneryProfiles: sceneryProfiles,
        weatherProfiles: weatherProfiles,
        musicCues: musicCues,
        difficulties: [
            DifficultyDefinition(
                id: "solar-to-summit-standard",
                trafficDensityMultiplier: 1,
                opponentSpeedMultiplier: 1,
                timeLimitSeconds: 205,
                checkpointTimeBonusSeconds: 18,
                scoreMultiplier: 1
            )
        ],
        assets: AssetManifest(entries: assetDefinitions),
        budgets: ContentBudget(
            maximumSections: 16,
            maximumTotalRoadLength: 12_000,
            maximumSceneryInstances: 900,
            maximumTrafficVehicles: 24
        )
    )

    private static let route = RouteGraphDefinition(
        startSectionID: "coast-causeway",
        finishSectionIDs: ["peaks-summit-finish"],
        sections: [
            section(
                "coast-causeway", length: 850, curve: (0.05, 0.18, 0.22),
                elevation: (0, 8, 10), lanes: 3, width: 4, shoulder: 1.4,
                links: [("coast-solar-sweep", nil)]
            ),
            section(
                "coast-solar-sweep", length: 1_050, curve: (0.12, -0.48, -0.18),
                elevation: (8, 24, 28), lanes: 3, width: 4, shoulder: 1.2,
                links: [("coast-cliff-arc", nil)]
            ),
            section(
                "coast-cliff-arc", length: 900, curve: (-0.1, 0.58, 0.2),
                elevation: (24, 42, 48), lanes: 3, width: 3.9, shoulder: 1.1,
                links: [("city-rain-gate", nil)]
            ),
            section(
                "city-rain-gate", length: 760, curve: (0.08, -0.16, 0.05),
                elevation: (42, 48, 52), lanes: 4, width: 3.8, shoulder: 0.8,
                laneChanges: [LaneChangeDefinition(id: "city-merge-one", at: 620, laneCount: 3)],
                links: [("city-vanta-canyon", nil)]
            ),
            section(
                "city-vanta-canyon", length: 950, curve: (0.06, 0.36, 0.1),
                elevation: (48, 68, 72), lanes: 3, width: 3.9, shoulder: 0.7,
                links: [("city-fork", nil)]
            ),
            section(
                "city-fork", length: 520, curve: (0, 0.08, 0),
                elevation: (68, 72, 74), lanes: 4, width: 3.8, shoulder: 0.8,
                links: [
                    ("city-axis-tunnel", "gateway-choice"),
                    ("peaks-storm-switchback", "gateway-choice")
                ]
            ),
            section(
                "city-axis-tunnel", length: 720, curve: (0, -0.22, -0.08),
                elevation: (72, 60, 76), lanes: 3, width: 4, shoulder: 0.9,
                links: [("city-orbit-skyway", nil)]
            ),
            section(
                "city-orbit-skyway", length: 940, curve: (-0.08, 0.49, 0.18),
                elevation: (60, 132, 138), lanes: 3, width: 4.1, shoulder: 1,
                links: [("peaks-relay-ridge", nil)]
            ),
            section(
                "peaks-storm-switchback", length: 980, curve: (0.1, -0.76, 0.24),
                elevation: (74, 196, 212), lanes: 2, width: 3.7, shoulder: 1.2,
                links: [("peaks-relay-ridge", nil)]
            ),
            section(
                "peaks-relay-ridge", length: 900, curve: (-0.12, 0.65, 0.16),
                elevation: (196, 244, 252), lanes: 2, width: 3.8, shoulder: 1.3,
                links: [("peaks-summit-finish", nil)]
            ),
            section(
                "peaks-summit-finish", length: 780, curve: (0.08, -0.2, 0),
                elevation: (244, 270, 274), lanes: 3, width: 3.9, shoulder: 1.5,
                links: []
            )
        ],
        checkpoints: [
            CheckpointDefinition(id: "coast-exit-checkpoint", sectionID: "coast-cliff-arc", at: 760, order: 0, isRequired: true),
            CheckpointDefinition(id: "city-fork-checkpoint", sectionID: "city-fork", at: 360, order: 1, isRequired: true),
            CheckpointDefinition(id: "summit-checkpoint", sectionID: "peaks-relay-ridge", at: 760, order: 2, isRequired: true)
        ],
        forks: [
            ForkDefinition(
                id: "gateway-choice",
                sectionID: "city-fork",
                at: 390,
                destinationSectionIDs: ["city-axis-tunnel", "peaks-storm-switchback"],
                defaultDestinationSectionID: "city-axis-tunnel"
            )
        ]
    )

    private static let palettes = [
        PaletteDefinition(
            id: "sunset-coast-palette",
            skyTopHex: "#35115C", skyBottomHex: "#F05A61", roadHex: "#171A32",
            shoulderHex: "#27324D", laneMarkerHex: "#DDFBFF",
            primaryAccentHex: "#25E6E0", secondaryAccentHex: "#FFD06A", fogHex: "#C63D8F"
        ),
        PaletteDefinition(
            id: "neon-city-palette",
            skyTopHex: "#080B24", skyBottomHex: "#39205C", roadHex: "#101522",
            shoulderHex: "#202944", laneMarkerHex: "#E8F7FF",
            primaryAccentHex: "#FF3C91", secondaryAccentHex: "#55C7FF", fogHex: "#253C66"
        ),
        PaletteDefinition(
            id: "midnight-peaks-palette",
            skyTopHex: "#030A20", skyBottomHex: "#102A47", roadHex: "#0C1320",
            shoulderHex: "#233143", laneMarkerHex: "#E6F2FF",
            primaryAccentHex: "#75F4C8", secondaryAccentHex: "#6AB7FF", fogHex: "#7359B7"
        )
    ]

    private static let trafficProfiles = [
        TrafficProfileDefinition(
            id: "sunset-coast-traffic", baseDensity: 0.24, maximumVehicles: 9,
            minimumHeadway: 2.1, speedRange: .init(lowerBound: 72, upperBound: 98),
            vehicleAssetIDs: ["coast-cruiser-placeholder"]
        ),
        TrafficProfileDefinition(
            id: "neon-city-traffic", baseDensity: 0.62, maximumVehicles: 18,
            minimumHeadway: 1.45, speedRange: .init(lowerBound: 58, upperBound: 92),
            vehicleAssetIDs: ["city-commuter-placeholder", "city-hauler-placeholder"]
        ),
        TrafficProfileDefinition(
            id: "midnight-peaks-traffic", baseDensity: 0.2, maximumVehicles: 7,
            minimumHeadway: 2.5, speedRange: .init(lowerBound: 62, upperBound: 84),
            vehicleAssetIDs: ["peaks-runner-placeholder"]
        )
    ]

    private static let sceneryProfiles = [
        SceneryProfileDefinition(id: "sunset-coast-scenery", bands: [
            band("coast-horizon", side: .left, distance: (150, 1_200), lateral: (70, 180), spacing: 420, assets: ["striped-sun-placeholder", "angular-coast-placeholder"], maximum: 28),
            band("coast-palms", side: .both, distance: (30, 420), lateral: (12, 38), spacing: 85, assets: ["palm-fan-placeholder"], maximum: 42)
        ]),
        SceneryProfileDefinition(id: "neon-city-scenery", bands: [
            band("city-blocks", side: .both, distance: (40, 700), lateral: (18, 90), spacing: 55, assets: ["skyline-block-placeholder", "overpass-placeholder"], maximum: 150),
            band("city-signs", side: .both, distance: (25, 360), lateral: (12, 42), spacing: 96, assets: ["fictional-sign-placeholder"], maximum: 54),
            band("city-tunnel-bays", side: .both, distance: (10, 240), lateral: (7, 18), spacing: 32, assets: ["tunnel-bay-placeholder"], maximum: 72)
        ]),
        SceneryProfileDefinition(id: "midnight-peaks-scenery", bands: [
            band("peaks-horizon", side: .both, distance: (180, 1_500), lateral: (80, 240), spacing: 260, assets: ["wireframe-mountain-placeholder", "star-field-placeholder", "aurora-placeholder"], maximum: 90),
            band("peaks-relays", side: .right, distance: (70, 620), lateral: (18, 65), spacing: 310, assets: ["relay-beacon-placeholder"], maximum: 12)
        ])
    ]

    private static let weatherProfiles = [
        WeatherDefinition(id: "sunset-coast-weather", kind: .dust, intensity: 0.16, visibility: 0.88, roadGrip: 1, particleAssetID: nil),
        WeatherDefinition(id: "neon-city-weather", kind: .rain, intensity: 0.42, visibility: 0.76, roadGrip: 0.88, particleAssetID: nil),
        WeatherDefinition(id: "midnight-peaks-weather", kind: .fog, intensity: 0.34, visibility: 0.68, roadGrip: 0.82, particleAssetID: nil)
    ]

    private static let musicCues = [
        MusicCueDefinition(id: "coastline-pulse", trigger: .stageStart, assetID: "coastline-pulse-placeholder", loop: true, crossfadeSeconds: 3.2),
        MusicCueDefinition(id: "vertical-current", trigger: .checkpoint, assetID: "vertical-current-placeholder", loop: true, crossfadeSeconds: 3.6),
        MusicCueDefinition(id: "summit-signal", trigger: .finalStretch, assetID: "summit-signal-placeholder", loop: true, crossfadeSeconds: 5.2)
    ]

    private static let themeZones = [
        ThemeZoneDefinition(
            id: "sunset-coast", displayName: "Sunset Coast",
            sectionIDs: ["coast-causeway", "coast-solar-sweep", "coast-cliff-arc"],
            paletteID: "sunset-coast-palette", trafficProfileID: "sunset-coast-traffic",
            sceneryProfileID: "sunset-coast-scenery", weatherProfileID: "sunset-coast-weather",
            musicCueID: "coastline-pulse",
            silhouetteIdentity: "Low striped solar disc, asymmetric cliffs, and sparse fan palms."
        ),
        ThemeZoneDefinition(
            id: "neon-city", displayName: "Neon City",
            sectionIDs: ["city-rain-gate", "city-vanta-canyon", "city-fork", "city-axis-tunnel", "city-orbit-skyway"],
            paletteID: "neon-city-palette", trafficProfileID: "neon-city-traffic",
            sceneryProfileID: "neon-city-scenery", weatherProfileID: "neon-city-weather",
            musicCueID: "vertical-current",
            silhouetteIdentity: "Stacked service towers, elevated transit, and deep tunnel portals."
        ),
        ThemeZoneDefinition(
            id: "midnight-peaks", displayName: "Midnight Peaks",
            sectionIDs: ["peaks-storm-switchback", "peaks-relay-ridge", "peaks-summit-finish"],
            paletteID: "midnight-peaks-palette", trafficProfileID: "midnight-peaks-traffic",
            sceneryProfileID: "midnight-peaks-scenery", weatherProfileID: "midnight-peaks-weather",
            musicCueID: "summit-signal",
            silhouetteIdentity: "Layered wire peaks, aurora ribbons, switchbacks, and one relay beacon."
        )
    ]

    private static let transitions = [
        ThemeTransitionDefinition(id: "coast-to-city", fromSectionID: "coast-cliff-arc", toSectionID: "city-rain-gate", length: 340, paletteBlendSeconds: 3.2, sceneryCrossfadeSeconds: 4, musicCrossfadeSeconds: 3.6, preloadDistance: 900),
        ThemeTransitionDefinition(id: "city-to-storm", fromSectionID: "city-fork", toSectionID: "peaks-storm-switchback", length: 390, paletteBlendSeconds: 4, sceneryCrossfadeSeconds: 5, musicCrossfadeSeconds: 5.2, preloadDistance: 1_100),
        ThemeTransitionDefinition(id: "skyway-to-summit", fromSectionID: "city-orbit-skyway", toSectionID: "peaks-relay-ridge", length: 420, paletteBlendSeconds: 4.2, sceneryCrossfadeSeconds: 5.5, musicCrossfadeSeconds: 5.2, preloadDistance: 1_200)
    ]

    private static let placeholders: [ProceduralPlaceholderDefinition] = [
        placeholder("coast-cruiser-placeholder", .vehicleSilhouette, "secondary-accent"),
        placeholder("city-commuter-placeholder", .vehicleSilhouette, "primary-accent"),
        placeholder("city-hauler-placeholder", .vehicleSilhouette, "shoulder"),
        placeholder("peaks-runner-placeholder", .vehicleSilhouette, "secondary-accent"),
        placeholder("striped-sun-placeholder", .stripedSunDisc, "secondary-accent", animation: "slow-horizon-descent"),
        placeholder("angular-coast-placeholder", .angularCoast, "shoulder"),
        placeholder("palm-fan-placeholder", .palmFan, "road", animation: "low-wind-sway"),
        placeholder("skyline-block-placeholder", .skylineBlock, "road", animation: "window-cluster-cycle"),
        placeholder("fictional-sign-placeholder", .fictionalSignPanel, "primary-accent", animation: "slow-sign-sequence", label: "VANTA PORT"),
        placeholder("overpass-placeholder", .overpassSpan, "shoulder", animation: "transit-light-pass"),
        placeholder("tunnel-bay-placeholder", .tunnelBay, "secondary-accent", animation: "asymmetric-bay-pulse", label: "AXIS RELAY"),
        placeholder("wireframe-mountain-placeholder", .wireframeMountain, "secondary-accent"),
        placeholder("star-field-placeholder", .starField, "lane-marker", animation: "reduce-flash-safe-twinkle"),
        placeholder("aurora-placeholder", .auroraRibbon, "primary-accent", animation: "slow-opacity-wave"),
        placeholder("relay-beacon-placeholder", .relayBeacon, "secondary-accent", animation: "steady-guidance-core", label: "NORTHLINE RELAY"),
        placeholder("coastline-pulse-placeholder", .proceduralMusic, "music", animation: "108-bpm-a-minor"),
        placeholder("vertical-current-placeholder", .proceduralMusic, "music", animation: "122-bpm-c-minor"),
        placeholder("summit-signal-placeholder", .proceduralMusic, "music", animation: "116-bpm-e-minor")
    ]

    private static var assetDefinitions: [AssetDefinition] {
        placeholders.map { placeholder in
            let kind: AssetKind
            switch placeholder.primitive {
            case .vehicleSilhouette:
                kind = .vehicle
            case .proceduralMusic:
                kind = .audio
            default:
                kind = .image
            }
            return AssetDefinition(
                id: placeholder.assetID,
                kind: kind,
                resourceName: "procedural://\(placeholder.assetID)"
            )
        }
    }

    static func routeGraph() -> RouteGraph {
        let checkpointSections = Set(document.stage.route.checkpoints.map(\.sectionID))
        let checkpointAward = document.difficulties.first?.checkpointTimeBonusSeconds ?? 0
        let stages = document.stage.route.sections.map { section in
            let branches = section.links.enumerated().map { index, link in
                RouteBranch(
                    id: link.forkID.map { "\($0)-\(index)" }
                        ?? "\(section.id)-to-\(link.destinationSectionID)",
                    direction: section.links.count > 1
                        ? (index == 0 ? .left : .right)
                        : .straight,
                    destinationStageID: link.destinationSectionID,
                    previewName: themeZones
                        .first { $0.sectionIDs.contains(link.destinationSectionID) }?
                        .displayName
                        ?? link.destinationSectionID.replacingOccurrences(of: "-", with: " ").capitalized
                )
            }
            return RouteStage(
                id: section.id,
                displayName: section.id.replacingOccurrences(of: "-", with: " ").capitalized,
                environmentID: bundle.themeID(for: section.id) ?? document.stage.paletteID,
                distance: section.length,
                checkpointTimeAward: checkpointSections.contains(section.id) ? checkpointAward : 0,
                branches: branches
            )
        }
        return RouteGraph(
            startStageID: document.stage.route.startSectionID,
            stages: stages,
            forkDecisionDistance: 500,
            minimumForkDecisionTime: 3
        )
    }

    private static func section(
        _ id: String,
        length: Double,
        curve: (Double, Double, Double),
        elevation: (Double, Double, Double?),
        lanes: Int,
        width: Double,
        shoulder: Double,
        laneChanges: [LaneChangeDefinition] = [],
        links: [(String, String?)]
    ) -> RoadSectionDefinition {
        RoadSectionDefinition(
            id: id,
            length: length,
            curve: CurveDefinition(entry: curve.0, apex: curve.1, exit: curve.2),
            elevation: ElevationDefinition(
                startMeters: elevation.0,
                endMeters: elevation.1,
                crestMeters: elevation.2
            ),
            lanes: LaneDefinition(count: lanes, width: width, shoulderWidth: shoulder),
            laneChanges: laneChanges,
            links: links.map {
                RouteLinkDefinition(destinationSectionID: $0.0, forkID: $0.1)
            }
        )
    }

    private static func band(
        _ id: String,
        side: RoadSide,
        distance: (Double, Double),
        lateral: (Double, Double),
        spacing: Double,
        assets: [String],
        maximum: Int
    ) -> SceneryBandDefinition {
        SceneryBandDefinition(
            id: id,
            side: side,
            distanceRange: .init(lowerBound: distance.0, upperBound: distance.1),
            lateralRange: .init(lowerBound: lateral.0, upperBound: lateral.1),
            spacing: spacing,
            assetIDs: assets,
            maximumInstances: maximum
        )
    }

    private static func placeholder(
        _ id: String,
        _ primitive: ProceduralPlaceholderDefinition.Primitive,
        _ paletteRole: String,
        animation: String? = nil,
        label: String? = nil
    ) -> ProceduralPlaceholderDefinition {
        ProceduralPlaceholderDefinition(
            assetID: id,
            primitive: primitive,
            paletteRole: paletteRole,
            animationCue: animation,
            fictionalLabel: label
        )
    }
}
