import Foundation

enum RaceHUDWarning: Equatable, Sendable {
    case timeCritical
    case roadEdge
    case boostDepleted
}

enum HUDRouteProgressMarkerKind: String, Equatable, Codable, Sendable {
    case start
    case checkpoint
    case fork
    case finish
}

struct HUDRouteProgressMarker: Equatable, Codable, Identifiable, Sendable {
    let id: String
    let kind: HUDRouteProgressMarkerKind
    let position: Double
    let label: String
    let isReached: Bool
}

struct HUDMapPoint: Equatable, Codable, Sendable {
    let x: Double
    let y: Double
}

struct HUDMinimapMarker: Equatable, Codable, Identifiable, Sendable {
    let id: String
    let kind: HUDRouteProgressMarkerKind
    let point: HUDMapPoint
    let label: String
    let isReached: Bool
}

struct HUDMinimapSnapshot: Equatable, Codable, Sendable {
    let polyline: [HUDMapPoint]
    let markers: [HUDMinimapMarker]
    let playerPoint: HUDMapPoint
    let playerHeadingRadians: Double
    let progress: Double
}

struct HUDStandingEntry: Equatable, Codable, Identifiable, Sendable {
    let id: String
    let position: Int
    let label: String
    let gapMeters: Double
    let isPlayer: Bool
}

struct HUDForkPreview: Equatable, Codable, Sendable {
    let left: String?
    let right: String?
}

enum RaceHUDFeedback: Equatable, Sendable {
    case countdown(Int)
    case go
    case boostEngaged
    case checkpoint(number: Int)
    case checkpointBonus(number: Int, seconds: Int)
    case routeFork
    case forkPreview(left: String?, right: String?)
    case routeChosen(String)
    case finalStretch
    case score(source: ScoreSource, points: Int)
    case nearMiss(points: Int)
    case overtake(points: Int)
    case drift(multiplier: Double, points: Int)
    case comboIncreased(Double)
    case comboBroken
    case rankChanged(RaceRank)
    case crashTimePenalty(seconds: Int)
    case collision
    case finished
    case failed
}

struct RaceHUDSnapshot: Equatable, Sendable {
    /// Arcade display conversion: one simulation speed unit renders as 2.4 km/h, so base max speed 120 displays as 288 km/h.
    static let speedKilometersPerHourPerSimulationUnit = 2.4
    static let speedDisplayMaximumKPH = 300

    let speedMPH: Int
    let speedKPH: Int
    let speedDisplayFraction: Double
    let score: Int
    let formattedScore: String
    let timerSeconds: Int
    let timerDigitalText: String
    let countdownSeconds: Int?
    let stageNumber: Int
    let stageIndexInRun: Int
    let stageProgress: Double
    let routeProgressFraction: Double
    let routeProgressMarkers: [HUDRouteProgressMarker]
    let minimap: HUDMinimapSnapshot
    let standings: [HUDStandingEntry]
    let routeName: String?
    let comboMultiplier: Double?
    let boostFraction: Double
    let isBoostActive: Bool
    let phase: RacePhase
    let isFinalStretch: Bool
    let warning: RaceHUDWarning?

    static let initial = RaceHUDSnapshot(
        state: RaceState(),
        configuration: .standard
    )

    private init(
        speedMPH: Int,
        speedKPH: Int,
        speedDisplayFraction: Double,
        score: Int,
        formattedScore: String,
        timerSeconds: Int,
        timerDigitalText: String,
        countdownSeconds: Int?,
        stageNumber: Int,
        stageIndexInRun: Int,
        stageProgress: Double,
        routeProgressFraction: Double,
        routeProgressMarkers: [HUDRouteProgressMarker],
        minimap: HUDMinimapSnapshot,
        standings: [HUDStandingEntry],
        routeName: String?,
        comboMultiplier: Double?,
        boostFraction: Double,
        isBoostActive: Bool,
        phase: RacePhase,
        isFinalStretch: Bool,
        warning: RaceHUDWarning?
    ) {
        self.speedMPH = speedMPH
        self.speedKPH = speedKPH
        self.speedDisplayFraction = speedDisplayFraction
        self.score = score
        self.formattedScore = formattedScore
        self.timerSeconds = timerSeconds
        self.timerDigitalText = timerDigitalText
        self.countdownSeconds = countdownSeconds
        self.stageNumber = stageNumber
        self.stageIndexInRun = stageIndexInRun
        self.stageProgress = stageProgress
        self.routeProgressFraction = routeProgressFraction
        self.routeProgressMarkers = routeProgressMarkers
        self.minimap = minimap
        self.standings = standings
        self.routeName = routeName
        self.comboMultiplier = comboMultiplier
        self.boostFraction = boostFraction
        self.isBoostActive = isBoostActive
        self.phase = phase
        self.isFinalStretch = isFinalStretch
        self.warning = warning
    }

    init(state: RaceState, configuration: RaceConfiguration, trackLayout: TrackLayout? = nil) {
        let score = max(0, Int(state.score.rounded(.down)))
        let speedKPH = max(
            0,
            Int((state.speed * Self.speedKilometersPerHourPerSimulationUnit).rounded())
        )
        let minimap = HUDMinimapBuilder.make(state: state, trackLayout: trackLayout)
        let routeProgress = trackLayout == nil ? Self.routeProgressFraction(for: state) : minimap.progress
        let stageNumber = state.completedStageIDs.count + 1
        let currentStageID = state.currentStageID
        let timerSeconds = max(0, Int(state.timerRemaining.rounded(.up)))

        self.speedMPH = max(0, Int((state.speed * 2.236_936).rounded()))
        self.speedKPH = speedKPH
        self.speedDisplayFraction = (Double(speedKPH) / Double(Self.speedDisplayMaximumKPH))
            .clamped(to: 0...1)
        self.score = score
        self.formattedScore = String(format: "%07d", min(score, 9_999_999))
        self.timerSeconds = timerSeconds
        self.timerDigitalText = Self.digitalTimerText(seconds: timerSeconds)
        self.countdownSeconds = HUDCalloutMapper.countdownSecond(
            phase: state.phase,
            countdownRemaining: state.countdownRemaining
        )
        self.stageNumber = stageNumber
        self.stageIndexInRun = stageNumber
        self.stageProgress = state.stageProgress.clamped(to: 0...1)
        self.routeProgressFraction = routeProgress
        self.routeProgressMarkers = Self.routeProgressMarkers(progress: routeProgress)
        self.minimap = minimap
        self.standings = Self.standings(for: state)
        self.routeName = state.committedBranchIDs.last.map {
            $0.replacingOccurrences(of: "-", with: " ").uppercased()
        } ?? (currentStageID.isEmpty
            ? nil
            : currentStageID.replacingOccurrences(of: "-", with: " ").uppercased())
        self.comboMultiplier = state.combo.chainCount > 0 ? state.combo.multiplier : nil
        self.boostFraction = configuration.boost.capacity > 0
            ? (state.boostCharge / configuration.boost.capacity).clamped(to: 0...1)
            : 0
        self.isBoostActive = state.isBoostActive
        self.phase = state.phase
        self.isFinalStretch = state.phase == .racing
            && (routeProgress >= 0.86 || currentStageID.localizedCaseInsensitiveContains("final"))

        if state.phase == .racing, state.timerRemaining <= 10 {
            warning = .timeCritical
        } else if abs(state.lateralPosition) >= 0.9 {
            warning = .roadEdge
        } else if state.phase == .racing, state.boostCharge <= 0.05 {
            warning = .boostDepleted
        } else {
            warning = nil
        }
    }

    static func digitalTimerText(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let seconds = clamped % 60
        return String(format: "%d:%01d:%02d", hours, minutes, seconds)
    }

    static func standings(for state: RaceState) -> [HUDStandingEntry] {
        var racers: [(id: String, label: String, distance: Double, isPlayer: Bool)] = [
            ("player", "YOU", state.distance, true)
        ]
        let rivals = state.traffic
            .filter { $0.kind == .rival }
            .sorted { $0.distance > $1.distance }
            .prefix(4)
        for (index, rival) in rivals.enumerated() {
            racers.append((
                "rival-\(rival.id)",
                "RIVAL \(index + 1)",
                rival.distance,
                false
            ))
        }
        return racers
            .sorted { lhs, rhs in
                if lhs.distance == rhs.distance { return lhs.isPlayer && !rhs.isPlayer }
                return lhs.distance > rhs.distance
            }
            .enumerated()
            .map { index, racer in
                HUDStandingEntry(
                    id: racer.id,
                    position: index + 1,
                    label: racer.label,
                    gapMeters: racer.distance - state.distance,
                    isPlayer: racer.isPlayer
                )
            }
    }

    static func routeProgressFraction(for state: RaceState) -> Double {
        if state.phase == .finished {
            return 1
        }
        let estimatedStageCount = 3.0
        let completedStages = Double(min(state.completedStageIDs.count, Int(estimatedStageCount) - 1))
        return ((completedStages + state.stageProgress.clamped(to: 0...1)) / estimatedStageCount)
            .clamped(to: 0...1)
    }

    static func routeProgressMarkers(progress: Double) -> [HUDRouteProgressMarker] {
        [
            marker(id: "start", kind: .start, position: 0, label: "START", progress: progress),
            marker(id: "checkpoint-1", kind: .checkpoint, position: 0.36, label: "CP1", progress: progress),
            marker(id: "fork", kind: .fork, position: 0.42, label: "FORK", progress: progress),
            marker(id: "checkpoint-2", kind: .checkpoint, position: 0.68, label: "CP2", progress: progress),
            marker(id: "finish", kind: .finish, position: 1, label: "FINISH", progress: progress)
        ]
    }

    private static func marker(
        id: String,
        kind: HUDRouteProgressMarkerKind,
        position: Double,
        label: String,
        progress: Double
    ) -> HUDRouteProgressMarker {
        HUDRouteProgressMarker(
            id: id,
            kind: kind,
            position: position,
            label: label,
            isReached: progress + 0.001 >= position
        )
    }
}

struct RaceHUDUpdate: Equatable, Sendable {
    let snapshot: RaceHUDSnapshot
    let feedback: RaceHUDFeedback?
}

struct RaceHUDTracker: Sendable {
    private(set) var consumedEventCount = 0
    private(set) var consumedScoreEventCount = 0
    private(set) var consumedFeedbackEventCount = 0
    private(set) var consumedRunEventCount = 0
    private(set) var checkpointNumber = 0
    private var lastCountdownSecond: Int?

    mutating func update(
        state: RaceState,
        events: [RaceEvent],
        scoreEvents: [ScoreEvent] = [],
        feedbackEvents: [RaceFeedbackEvent] = [],
        runEvents: [RunEvent] = [],
        configuration: RaceConfiguration,
        trackLayout: TrackLayout? = nil
    ) -> RaceHUDUpdate {
        var feedback: RaceHUDFeedback?

        if consumedEventCount > events.count {
            consumedEventCount = 0
            checkpointNumber = 0
        }
        if consumedScoreEventCount > scoreEvents.count {
            consumedScoreEventCount = 0
        }
        if consumedFeedbackEventCount > feedbackEvents.count {
            consumedFeedbackEventCount = 0
        }
        if consumedRunEventCount > runEvents.count {
            consumedRunEventCount = 0
            checkpointNumber = 0
        }

        for event in events.dropFirst(consumedEventCount) {
            switch event {
            case .started:
                feedback = .go
            case .boostStarted:
                feedback = .boostEngaged
            case .boostEnded:
                break
            case .finished:
                feedback = .finished
            case .failed:
                feedback = .failed
            }
        }
        consumedEventCount = events.count

        if let skillScore = scoreEvents.dropFirst(consumedScoreEventCount).last(where: {
            ![.distance, .speed, .boost].contains($0.source)
        }) {
            feedback = HUDCalloutMapper.feedback(
                for: skillScore,
                comboMultiplier: state.combo.chainCount > 0 ? state.combo.multiplier : nil
            )
        }
        consumedScoreEventCount = scoreEvents.count

        for event in feedbackEvents.dropFirst(consumedFeedbackEventCount)
            where event.channels.contains(.hud) {
            if let mappedFeedback = HUDCalloutMapper.feedback(
                for: event.cue,
                state: state,
                configuration: configuration
            ) {
                feedback = mappedFeedback
            }
        }
        consumedFeedbackEventCount = feedbackEvents.count

        for event in runEvents.dropFirst(consumedRunEventCount) {
            if case .checkpointCrossed = event {
                checkpointNumber += 1
            }
            if let mappedFeedback = HUDCalloutMapper.feedback(
                for: event,
                checkpointNumber: checkpointNumber
            ) {
                feedback = mappedFeedback
            }
        }
        consumedRunEventCount = runEvents.count

        let countdownSecond = HUDCalloutMapper.countdownSecond(
            phase: state.phase,
            countdownRemaining: state.countdownRemaining
        )
        if let countdownSecond, countdownSecond != lastCountdownSecond {
            feedback = .countdown(countdownSecond)
        }
        lastCountdownSecond = countdownSecond

        return RaceHUDUpdate(
            snapshot: RaceHUDSnapshot(state: state, configuration: configuration, trackLayout: trackLayout),
            feedback: feedback
        )
    }
}

enum HUDMinimapBuilder {
    private struct RawPoint {
        let x: Double
        let y: Double
        let distance: Double
    }

    static func make(state: RaceState, trackLayout: TrackLayout?) -> HUDMinimapSnapshot {
        guard let trackLayout else {
            let progress = RaceHUDSnapshot.routeProgressFraction(for: state)
            return HUDMinimapSnapshot(
                polyline: [
                    HUDMapPoint(x: 0.08, y: 0.82),
                    HUDMapPoint(x: 0.38, y: 0.64),
                    HUDMapPoint(x: 0.56, y: 0.38),
                    HUDMapPoint(x: 0.88, y: 0.18)
                ],
                markers: RaceHUDSnapshot.routeProgressMarkers(progress: progress).map { marker in
                    HUDMinimapMarker(
                        id: marker.id,
                        kind: marker.kind,
                        point: HUDMapPoint(x: marker.position, y: 1 - marker.position),
                        label: marker.label,
                        isReached: marker.isReached
                    )
                },
                playerPoint: HUDMapPoint(x: progress, y: 1 - progress),
                playerHeadingRadians: 0,
                progress: progress
            )
        }

        let stages = representativeStages(for: state, in: trackLayout.routeGraph)
        guard !stages.isEmpty else {
            return make(state: state, trackLayout: nil)
        }

        var rawPoints: [RawPoint] = [RawPoint(x: 0, y: 0, distance: 0)]
        var markers: [(id: String, kind: HUDRouteProgressMarkerKind, distance: Double, label: String)] = []
        var x = 0.0
        var y = 0.0
        var heading = 0.0
        var distanceOffset = 0.0

        for stage in stages {
            let profile = trackLayout.profile(for: stage.id)
            let sampleCount = max(8, min(42, Int((stage.distance / 90).rounded(.up))))
            let step = stage.distance / Double(sampleCount)
            for index in 1...sampleCount {
                let localDistance = min(stage.distance, Double(index) * step)
                let curvature = profile.curvature(at: localDistance)
                heading += curvature * TrackSectionProfile.radiansPerMeterAtFullCurve * step
                x += sin(heading) * step
                y += cos(heading) * step
                rawPoints.append(RawPoint(x: x, y: y, distance: distanceOffset + localDistance))
            }

            for marker in trackLayout.markers(for: stage.id) {
                guard let kind = minimapKind(for: marker.kind) else { continue }
                let globalDistance = distanceOffset + marker.distanceInStage
                if !markers.contains(where: { $0.kind == kind && abs($0.distance - globalDistance) < 1 }) {
                    markers.append((
                        "\(stage.id)-\(marker.kind.rawValue)",
                        kind,
                        globalDistance,
                        label(for: kind)
                    ))
                }
            }
            distanceOffset += stage.distance
        }

        let totalDistance = max(distanceOffset, 1)
        let progress = (state.distance / totalDistance).clamped(to: 0...1)
        let normalized = normalize(rawPoints)
        let player = pointAndHeading(at: progress * totalDistance, raw: rawPoints, normalized: normalized)
        let markerSnapshots = markers.map { marker in
            let mapped = pointAndHeading(at: marker.distance, raw: rawPoints, normalized: normalized)
            let position = (marker.distance / totalDistance).clamped(to: 0...1)
            return HUDMinimapMarker(
                id: marker.id,
                kind: marker.kind,
                point: mapped.point,
                label: marker.label,
                isReached: progress + 0.001 >= position
            )
        }

        return HUDMinimapSnapshot(
            polyline: normalized.map(\.point),
            markers: markerSnapshots,
            playerPoint: player.point,
            playerHeadingRadians: player.heading,
            progress: progress
        )
    }

    private static func representativeStages(for state: RaceState, in graph: RouteGraph) -> [RouteStage] {
        var stages: [RouteStage] = []
        var stageID = graph.startStageID
        var consumedBranches = 0
        var visited: Set<String> = []
        while let stage = graph.stage(id: stageID), !visited.contains(stageID), stages.count < 8 {
            visited.insert(stageID)
            stages.append(stage)
            guard !stage.branches.isEmpty else { break }
            let committed = consumedBranches < state.committedBranchIDs.count
                ? state.committedBranchIDs[consumedBranches]
                : nil
            let branch = committed.flatMap { id in stage.branches.first { $0.id == id } }
                ?? stage.branches.first { $0.destinationStageID == state.currentStageID }
                ?? stage.branches.first
            guard let branch else { break }
            if committed != nil { consumedBranches += 1 }
            stageID = branch.destinationStageID
        }
        return stages
    }

    private static func minimapKind(for kind: TrackZoneKind) -> HUDRouteProgressMarkerKind? {
        switch kind {
        case .startGrid: .start
        case .startLine: nil
        case .checkpoint: .checkpoint
        case .forkSplit: .fork
        case .finishLine: .finish
        }
    }

    private static func label(for kind: HUDRouteProgressMarkerKind) -> String {
        switch kind {
        case .start: "S"
        case .checkpoint: "CP"
        case .fork: "FK"
        case .finish: "F"
        }
    }

    private static func normalize(_ points: [RawPoint]) -> [(point: HUDMapPoint, raw: RawPoint)] {
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 1
        let spanX = max(maxX - minX, 1)
        let spanY = max(maxY - minY, 1)
        let scale = max(spanX, spanY)
        let pad = 0.08
        return points.map { raw in
            let x = ((raw.x - minX) / scale + (scale - spanX) / scale / 2)
                .clamped(to: 0...1)
            let y = (1 - ((raw.y - minY) / scale + (scale - spanY) / scale / 2))
                .clamped(to: 0...1)
            return (
                HUDMapPoint(
                    x: pad + x * (1 - pad * 2),
                    y: pad + y * (1 - pad * 2)
                ),
                raw
            )
        }
    }

    private static func pointAndHeading(
        at distance: Double,
        raw: [RawPoint],
        normalized: [(point: HUDMapPoint, raw: RawPoint)]
    ) -> (point: HUDMapPoint, heading: Double) {
        guard normalized.count >= 2 else {
            return (HUDMapPoint(x: 0.5, y: 0.5), 0)
        }
        let clampedDistance = distance.clamped(to: (raw.first?.distance ?? 0)...(raw.last?.distance ?? 1))
        let upperIndex = max(1, raw.firstIndex { $0.distance >= clampedDistance } ?? raw.count - 1)
        let lowerIndex = upperIndex - 1
        let lower = raw[lowerIndex]
        let upper = raw[upperIndex]
        let lowerPoint = normalized[lowerIndex].point
        let upperPoint = normalized[upperIndex].point
        let span = max(upper.distance - lower.distance, 0.000_1)
        let t = ((clampedDistance - lower.distance) / span).clamped(to: 0...1)
        let point = HUDMapPoint(
            x: lowerPoint.x + (upperPoint.x - lowerPoint.x) * t,
            y: lowerPoint.y + (upperPoint.y - lowerPoint.y) * t
        )
        let heading = atan2(upperPoint.x - lowerPoint.x, -(upperPoint.y - lowerPoint.y))
        return (point, heading)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
