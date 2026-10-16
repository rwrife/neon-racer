# Performance budgets and profiling companion

The single authoritative performance contract — minimum device class, numeric
budgets, quality tiers, and the sign-off baseline table — is
[`docs/performance.md`](../docs/performance.md) (issue #47 consolidated the two
historical spec documents; this file keeps only the non-budget material).

Do not record budgets or baseline rows here. Update `docs/performance.md`.

## Sign-off target

See `docs/performance.md` for the minimum-device class and every measurable
budget. Performance acceptance is measured on a physical device in a Release
build installed from Xcode, not in Simulator. Faster and ProMotion devices are
useful secondary coverage but cannot replace the minimum-device run.

## Quality tiers

`CosmeticQualityConfiguration` is the single typed definition for effect cost,
particle density, scenery density, render-target scale, and glow. The default
is `balanced`. For profiling, set the `NEON_RACER_QUALITY_TIER` scheme
environment variable to `efficiency`, `balanced`, or `fidelity`.

Quality is intentionally absent from `RaceSimulation` and `RaceConfiguration`.
Automatic thermal fallback may only replace the rendering configuration; it must
never alter fixed timestep, controls, collision/traffic decisions, scoring,
stage geometry, or seeded random-number consumption.

## Native effects stack

`NeonEffectsStack` renders bounded, SpriteKit-native overlays and pooled motion
effects above the world and below a separate `crisp-hud` node tree. Ordering is
world glow, exhaust/smoke/trails/sparks, speed streaks and heat haze, color
grade, scanlines/chromatic edge treatment/vignette, collision flash, then HUD.

Each effect has a typed enable switch and clamped `0...1` intensity. Efficiency
disables heat haze, chromatic separation, and sparks; balanced scales expensive
effects; fidelity uses the full bounded pools. Reduce Motion clamps moving
effects to 18% and limits their speed driver. Reduce Flashes clamps bloom,
color/chromatic treatment, and collision flash. DEBUG builds report active
effects and pool occupancy; tap an effect name to toggle it. Nodes are created
once and particle slots are recycled without per-emission `SKAction`s.

## Profiling procedure

1. Disable Low Power Mode, reboot the phone, let it cool to nominal, and
   disconnect other debug sessions. Install a Release build with the chosen
   tier and use the same stage, seed, and input script for every comparison.
2. First use a DEBUG build with **Points of Interest + Time Profiler** to
   inspect the `Frame`, `Simulation`, `Road Projection`, and `Effects`
   signposts. Then repeat the cold launch, full race, and two retries with a
   Release build for acceptance numbers. Export p50/p95 timings and inspect CPU
   call trees for regressions.
3. Repeat with **Core Animation** (and Metal System Trace once Metal rendering
   exists). Record frame hitches, GPU duration, draw calls, and live node
   count. The DEBUG overlay provides FPS, smoothed frame time, vehicle count,
   segment count, total node count, environment visible-node/estimated-draw
   counts, effects/pool counts, and tier; acceptance numbers still come from
   the Release trace.
4. Run **Allocations + Leaks** through the same three-run scenario. Mark
   generations after each finish/retry, record peak resident and texture
   memory, and investigate any unbounded generation growth or leak.
5. Run a 20-minute race/retry loop with **Energy Log**. Record thermal
   transitions, energy impact, battery state, brightness, ambient conditions,
   and whether cosmetic fallback occurred.
6. Save `.trace` files outside source control, add measured numbers to the
   baseline table in `docs/performance.md`, and include device model, OS,
   build/commit, tier, scenario, and regressions in the PR.

The current scene has no AI or Metal render path. SpriteKit effects use
fixed-capacity pools, and stage content is loaded before scene construction.
Add signposts to new asynchronous or Metal boundaries when introduced,
preserving the same category and cosmetic-only tier rule.
