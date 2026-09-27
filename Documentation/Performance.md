# Performance budgets and profiling

## Sign-off target

The minimum physical-device class is **iPhone 11 (A13, 4 GB RAM, 60 Hz)** running the
minimum supported iOS release. Performance acceptance is measured on that class in a
Release build installed from Xcode, not in Simulator. Faster and ProMotion devices are
useful secondary coverage but cannot replace the minimum-device run.

## Measurable budgets

Measure a representative complete race plus two immediate retries after a cold launch.
Report median and 95th percentile (p95); a pass requires all of the following:

| Area | Budget on minimum device |
| --- | --- |
| Frame pacing | 60 FPS target; p95 frame time <= 16.67 ms; fewer than 1% frames > 20 ms |
| CPU simulation | p95 <= 2.0 ms per rendered frame |
| CPU render submission / road projection | p95 <= 4.0 ms per frame |
| GPU | p95 <= 10.0 ms; no sustained GPU-bound interval longer than 2 s |
| Scene complexity | <= 250 live nodes and <= 100 draw calls in representative gameplay |
| Texture memory | <= 256 MB resident texture allocation |
| Process memory | <= 350 MB peak resident; <= 5 MB growth between retry 1 and retry 3 |
| Transient allocation | <= 128 KB/frame average during steady-state racing |
| Stage load | <= 2.0 s cold, <= 0.75 s warm, measured from selection to first playable frame |
| Thermal / energy | 20-minute loop remains nominal or fair; serious state must select a lower cosmetic tier |

Record actual baselines in the table below. Do not mark optimization complete while any
entry is `pending`.

| Build / commit | Device / OS | Scenario | FPS p95 | CPU sim p95 | CPU render p95 | GPU p95 | Peak / retry growth | Thermal | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| pending | iPhone 11 / minimum iOS | Full race + 2 retries | pending | pending | pending | pending | pending | pending | pending |

## Quality tiers

`CosmeticQualityConfiguration` is the single typed definition for effect cost, particle
density, scenery density, render-target scale, and glow. The default is `balanced`.
For profiling, set the `NEON_RACER_QUALITY_TIER` scheme environment variable to
`efficiency`, `balanced`, or `fidelity`.

Quality is intentionally absent from `RaceSimulation` and `RaceConfiguration`.
Automatic thermal fallback may only replace the rendering configuration; it must never
alter fixed timestep, controls, collision/traffic decisions, scoring, stage geometry, or
seeded random-number consumption.

## Profiling procedure

1. Disable Low Power Mode, reboot the phone, let it cool to nominal, and disconnect other
   debug sessions. Install a Release build with the chosen tier and use the same stage,
   seed, and input script for every comparison.
2. First use a DEBUG build with **Points of Interest + Time Profiler** to inspect the
   `Frame`, `Simulation`, `Road Projection`, and `Effects` signposts. Then repeat the
   cold launch, full race, and two retries with a Release build for acceptance numbers.
   Export p50/p95 timings and inspect CPU call trees for regressions.
3. Repeat with **Core Animation** (and Metal System Trace once Metal rendering exists).
   Record frame hitches, GPU duration, draw calls, and live node count. The DEBUG overlay
   provides FPS, smoothed frame time, vehicle count, segment count, node count, and tier;
   acceptance numbers still come from the Release trace.
4. Run **Allocations + Leaks** through the same three-run scenario. Mark generations
   after each finish/retry, record peak resident and texture memory, and investigate any
   unbounded generation growth or leak.
5. Run a 20-minute race/retry loop with **Energy Log**. Record thermal transitions,
   energy impact, battery state, brightness, ambient conditions, and whether cosmetic
   fallback occurred.
6. Save `.trace` files outside source control, add measured numbers to the baseline table,
   and include device model, OS, build/commit, tier, scenario, and regressions in the PR.

The current placeholder scene has no AI, particles, asynchronous stage loader, or Metal
render path. Add signposts to those boundaries when they are introduced, preserving the
same category and cosmetic-only tier rule.
