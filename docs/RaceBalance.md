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
speed ceiling, and awards explicit boost-risk points while active. It recharges
only while the boost command is released, preventing an empty held button from
auto-pulsing. Score is an auditable sum of distance and boost points, and rank thresholds are
profile-owned. Representative full-throttle runs establish bronze without
boost, silver from spending the initial charge, and gold from releasing boost
long enough to recharge it.

Every shipped profile must pass `validationErrors`. Tests also lock traffic
bounds, rank boundaries, boost depletion/recharge, and the measurable advantage
of intentional boost use.

Collision penalties, recovery windows, checkpoint margins, route multipliers,
and rival pressure remain untuned until those gameplay systems exist.
