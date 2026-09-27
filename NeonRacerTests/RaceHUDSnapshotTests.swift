import Testing

#if canImport(NeonRacerCore)
@testable import NeonRacerCore
#else
@testable import NeonRacer
#endif

struct RaceHUDSnapshotTests {
    @Test
    func snapshotFormatsSimulationValuesAndPrioritizesUrgentWarnings() {
        var state = RaceState(
            timerRemaining: 9.2,
            boostCharge: 0,
            stageProgress: 0.5,
            phase: .racing
        )
        state.speed = 10
        state.scoreInputs.distancePoints = 123.9
        state.lateralPosition = 0.95

        let snapshot = RaceHUDSnapshot(state: state, configuration: .standard)

        #expect(snapshot.speedMPH == 22)
        #expect(snapshot.speedKPH == 24)
        #expect(abs(snapshot.speedDisplayFraction - 0.08) < 0.0001)
        #expect(snapshot.score == 123)
        #expect(snapshot.formattedScore == "0000123")
        #expect(snapshot.timerSeconds == 10)
        #expect(snapshot.stageProgress == 0.5)
        #expect(abs(snapshot.routeProgressFraction - (0.5 / 3.0)) < 0.0001)
        #expect(snapshot.routeProgressMarkers.map(\.kind) == [.start, .checkpoint, .fork, .checkpoint, .finish])
        #expect(snapshot.boostFraction == 0)
        #expect(snapshot.warning == .timeCritical)
        #expect(snapshot.routeName == nil)
        #expect(snapshot.comboMultiplier == nil)
    }

    @Test
    func snapshotConvertsBaseMaximumSpeedToArcadeKilometersPerHour() {
        var state = RaceState(stageProgress: 1, phase: .racing)
        state.speed = RaceConfiguration.standard.maximumSpeed

        let snapshot = RaceHUDSnapshot(state: state, configuration: .standard)

        #expect(snapshot.speedKPH == 288)
        #expect(abs(snapshot.speedDisplayFraction - 0.96) < 0.0001)
    }

    @Test
    func snapshotTracksStageIndexAndRouteMarkerReachability() {
        var state = RaceState(stageProgress: 0.5, phase: .racing)
        state.completedStageIDs = ["neon-causeway"]
        state.currentStageID = "harbor-sprint"

        let snapshot = RaceHUDSnapshot(state: state, configuration: .standard)

        #expect(snapshot.stageIndexInRun == 2)
        #expect(abs(snapshot.routeProgressFraction - 0.5) < 0.0001)
        #expect(snapshot.routeProgressMarkers.first { $0.kind == .fork }?.isReached == true)
        #expect(snapshot.routeProgressMarkers.first { $0.id == "checkpoint-2" }?.isReached == false)
    }

    @Test
    func snapshotBuildsCurvedMinimapFromTrackLayout() {
        let routeGraph = RouteGraph.neonForkFixture(totalDistance: 4_800)
        let trackLayout = TrackLayout(routeGraph: routeGraph)
        var state = RaceSimulation(configuration: .standard, routeGraph: routeGraph).state
        state.distance = 960

        let snapshot = RaceHUDSnapshot(
            state: state,
            configuration: .standard,
            trackLayout: trackLayout
        )

        #expect(snapshot.minimap.polyline.count > 20)
        #expect(snapshot.minimap.markers.contains { $0.kind == .fork })
        #expect(snapshot.minimap.markers.contains { $0.kind == .finish })
        #expect(snapshot.minimap.polyline.allSatisfy { point in
            (0...1).contains(point.x) && (0...1).contains(point.y)
        })
        #expect(abs(snapshot.minimap.progress - 0.2) < 0.04)
        #expect(snapshot.routeProgressFraction == snapshot.minimap.progress)
    }

    @Test
    func snapshotFormatsDigitalTimerAndRivalStandings() {
        var state = RaceState(timerRemaining: 12.1, phase: .racing)
        state.distance = 1_000
        state.traffic = [
            TrafficVehicleState(
                id: 7,
                kind: .rival,
                distance: 1_130,
                lateralPosition: 0.2,
                speed: 80,
                halfWidth: 0.15
            ),
            TrafficVehicleState(
                id: 8,
                kind: .commuter,
                distance: 1_200,
                lateralPosition: -0.2,
                speed: 70,
                halfWidth: 0.15
            ),
            TrafficVehicleState(
                id: 9,
                kind: .rival,
                distance: 940,
                lateralPosition: -0.2,
                speed: 74,
                halfWidth: 0.15
            )
        ]

        let snapshot = RaceHUDSnapshot(state: state, configuration: .standard)

        #expect(snapshot.timerDigitalText == "0:0:13")
        #expect(snapshot.standings.map(\.label) == ["RIVAL 1", "YOU", "RIVAL 2"])
        #expect(snapshot.standings.first?.position == 1)
        #expect(snapshot.standings.first?.gapMeters == 130)
    }

    @Test
    func trackerEmitsOneShotEventsAndProgressCheckpoints() {
        var tracker = RaceHUDTracker()
        let state = RaceState(stageProgress: 0.26, phase: .racing)
        let events: [RaceEvent] = [.started(time: 0)]
        let checkpoint = RunEvent.checkpointCrossed(
            time: 2,
            completedStageID: "entry",
            nextStageID: "fork",
            timeAward: 12
        )

        let first = tracker.update(
            state: state,
            events: events,
            runEvents: [checkpoint],
            configuration: .standard
        )
        let repeated = tracker.update(
            state: state,
            events: events,
            runEvents: [checkpoint],
            configuration: .standard
        )

        #expect(first.feedback == .checkpointBonus(number: 1, seconds: 12))
        #expect(repeated.feedback == nil)
    }

    @Test
    func terminalEventsBecomeReadableFeedback() {
        var tracker = RaceHUDTracker()
        var state = RaceState(phase: .finished)

        let finish = tracker.update(
            state: state,
            events: [.finished(time: 42)],
            configuration: .standard
        )
        state.phase = .failed
        let failure = tracker.update(
            state: state,
            events: [.finished(time: 42), .failed(time: 43)],
            configuration: .standard
        )

        #expect(finish.feedback == .finished)
        #expect(failure.feedback == .failed)
    }

    @Test
    func calloutMapperCreatesArcadeScoreLanguage() {
        let nearMiss = scoreEvent(source: .nearMiss, points: 140)
        let overtake = scoreEvent(source: .overtake, points: 120)
        let drift = scoreEvent(source: .drift, points: 90, multiplier: 2)

        #expect(HUDCalloutMapper.feedback(for: nearMiss, comboMultiplier: nil) == .nearMiss(points: 140))
        #expect(HUDCalloutMapper.feedback(for: overtake, comboMultiplier: nil) == .overtake(points: 120))
        #expect(HUDCalloutMapper.feedback(for: drift, comboMultiplier: 2) == .drift(multiplier: 2, points: 90))
    }

    @Test
    func calloutMapperCreatesForkAndRankToasts() {
        let fork = RunEvent.forkPresented(
            time: 4,
            stageID: "neon-causeway",
            branches: [
                RouteBranch(
                    id: "left",
                    direction: .left,
                    destinationStageID: "harbor",
                    previewName: "Harbor"
                ),
                RouteBranch(
                    id: "right",
                    direction: .right,
                    destinationStageID: "skyway",
                    previewName: "Skyway"
                )
            ]
        )
        var state = RaceState(phase: .racing)
        state.scoreInputs.distancePoints = RaceConfiguration.standard.scoring.silverThreshold

        #expect(HUDCalloutMapper.feedback(for: fork, checkpointNumber: 0) == .forkPreview(left: "Harbor", right: "Skyway"))
        #expect(
            HUDCalloutMapper.feedback(
                for: .rankChanged,
                state: state,
                configuration: .standard
            ) == .rankChanged(.silver)
        )
    }

    @Test
    func calloutMapperCreatesCrashTimePenaltyFromCurrentAndFutureCueNames() {
        let state = RaceState(phase: .racing)

        #expect(
            HUDCalloutMapper.feedback(
                for: .crash,
                state: state,
                configuration: .standard
            ) == .crashTimePenalty(seconds: 3)
        )
        #expect(
            HUDCalloutMapper.feedback(
                for: .obstacleHit,
                state: state,
                configuration: .standard
            ) == .crashTimePenalty(seconds: 3)
        )
        #expect(HUDCalloutMapper.feedback(forRawCue: "timePenalty") == .crashTimePenalty(seconds: 3))
    }

    private func scoreEvent(
        source: ScoreSource,
        points: Double,
        multiplier: Double = 1
    ) -> ScoreEvent {
        ScoreEvent(
            sequence: 0,
            time: 0,
            source: source,
            basePoints: points / multiplier,
            multiplier: multiplier,
            points: points,
            totalAfter: points
        )
    }
}
