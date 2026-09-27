# Race balance

`RaceConfiguration` is the single source of truth for deterministic race tuning.
Choose `.novice`, `.standard`, or `.expert`; do not branch on difficulty inside
simulation systems or add hidden dynamic difficulty.

The profiles currently tune the slice supported by the simulation:

| Profile | Stage | Timer | Max speed | Traffic envelope | Initial/capacity boost |
| --- | ---: | ---: | ---: | ---: | ---: |
| Novice | 4,500 | 100 s | 112 | 0.14–0.30 | 7/7 s |
| Standard | 5,000 | 90 s | 120 | 0.20–0.42 | 4/6 s |
| Expert | 5,500 | 84 s | 128 | 0.28–0.56 | 3/5 s |

Boost is a deliberate limited resource. It supplies acceleration, raises the
speed ceiling, and awards explicit boost-risk points while active. Risk events
(overtakes, near misses, drifts, and checkpoints) earn charge, while passive
recharge occurs only while the boost command is released. The state machine
exposes unavailable, starting, active, and ending states and collision cooldowns
prevent immediate reactivation.

`GameplayScoreEvent` is the ingestion boundary for gameplay systems that are not
yet simulated here. Stable event IDs deduplicate physical passes, near misses,
drifts, checkpoints, and collisions; short per-source cooldowns and bounded
duration/intensity inputs prevent oscillation farming. The simulation does not
invent collision or traffic-contact events.

Every score mutation emits a typed `ScoreEvent`. `scoreResult` aggregates that
trace by source for distance, speed, boost, overtakes, near misses, drift,
checkpoints, position, finish, and collision penalties. Skilled actions grow a
capped combo multiplier; inactivity decays it, while prolonged slow driving or
a collision breaks it. Rank thresholds remain profile-owned.

Every shipped profile must pass `validationErrors`. Tests also lock traffic
bounds, rank boundaries, boost depletion/recharge, and the measurable advantage
of intentional boost use.

Event values are initial arcade defaults and should be play-tested once traffic,
collision, checkpoint, route, and rival-position systems provide production
events.
