# CyberRun performance budgets

CyberRun targets a sustained 60 FPS race on the minimum supported class: an A17 Pro-class iPhone with 8 GB RAM or better, running the current iOS deployment target. Simulator runs are useful for regressions, but final sign-off must be on a physical device because Simulator GPU, thermal, and MSAA behavior differ.

## Budgets

| Area | Budget |
| --- | --- |
| Frame pacing | 16.67 ms/frame target, no sustained periods below 55 FPS in a full race |
| CPU simulation | 2 ms/frame for simulation, AI, collision, scoring, and HUD update batching |
| Render submission | 5 ms/frame CPU side for road projection, streamer updates, traffic, particles, and effects |
| GPU | 8 ms/frame for SceneKit render, bloom/post, particles, skyline, and translucent grid |
| Nodes/draw-ish count | Keep active recursive nodes under 650 and geometry/draw-ish nodes under 420 in medium tier |
| Road/props | 14 road chunks; streamed props/traffic only inside the tier draw distance |
| Memory | App resident memory under 650 MB after loading; no sustained growth over three race/retry loops |
| Texture/transient allocations | Avoid per-frame texture/image allocation; transient allocations under 5 MB/s during races |
| Load time | Title-to-race interactive in under 3 seconds on the minimum device |
| Thermal | No escalation beyond `.fair` during a representative Release run; `.serious` or `.critical` must force low tier cosmetics |

## Render quality tiers

| Tier | Selection | Resolution scale | Bloom/post | Particles | Scenery/skyline | Draw distance | Antialiasing |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- |
| Low | Low-memory devices or serious/critical thermal state | 0.72x | Bloom off, post off | 40% | 55% | 560 m | None |
| Medium | Simulator default, 4-5 GB devices, or high tier under fair thermal state | 0.90x | Bloom on, post off | 70% | 80% | 720 m | 2x on device, none on Simulator |
| High | 6 GB+ physical devices in nominal thermal state | 1.00x | Bloom on, post on | 100% | 100% | 850 m | 4x on device, none on Simulator |

The player setting can force Low, Medium, or High, but thermal pressure still caps the effective tier so fallback remains cosmetic-only. Simulation configuration, random seeds, scoring, collision, and input handling are independent of tier.

## Profiling procedure

1. Build Release for the minimum physical device with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and code signing configured for the device.
2. Start a representative route, complete one warm-up run, then profile a full run with Instruments:
   - Time Profiler for `RaceSimulation.advance`, road projection, streamer updates, and HUD publication.
   - Allocations/Leaks for retry loops and stage transitions.
   - Metal/Core Animation for SceneKit frame pacing, overdraw, and render-target scale.
   - Energy Log for thermal behavior over repeated runs.
3. In Debug builds, launch with `UITestPerfOverlay` or enable Settings > Graphics > Performance Overlay to watch FPS, frame time, vehicles, segment count, recursive node count, draw-ish geometry count, pool use, and tier.
4. Repeat the run in Low, Medium, and High settings. Confirm score traces and final outcomes match for the same input/seed.
5. Record baseline FPS, memory high-water mark, thermal state, device model, iOS version, and route in this document when final physical-device profiling is performed.

## Current Simulator baseline

On the local iPhone 17 Pro Simulator running an auto-drive debug race, the pre-change renderer held about 55.7 FPS with the optimized HUD. After adding automatic Medium tier defaults, the same Simulator profile remains at approximately 56 FPS with no Simulator MSAA forced. Physical-device Release numbers are still required before optimization sign-off.
