# Physical-device performance sign-off

This is the **release gate** for measured performance. It is deliberately
fail-closed: `scripts/check_device_signoff.sh` exits non-zero (blocking
submission) until a dated physical-device measurement is recorded in
`docs/performance-device-evidence.md`.

Simulator results are useful for regression testing but do not satisfy this
gate, because Simulator GPU, thermal, and MSAA behavior differ from hardware.
No synthetic or Simulator number may be recorded here.

## Minimum device

The acceptance target is the minimum supported class defined in
`docs/performance.md`: an **A17 Pro-class iPhone with 8 GB RAM or better**,
running the current iOS deployment target. The headline goal is a sustained
**60 FPS** race on that device.

## Pass/fail thresholds

A run passes only when every threshold below is met on the minimum device in a
**Release** build. Report median and 95th percentile (p95) where a bound is a
per-frame time.

| Area | Threshold |
| --- | --- |
| Frame pacing | 16.67 ms/frame target; no sustained period below 55 FPS in a full race |
| CPU simulation | <= 2 ms/frame for simulation, AI, collision, scoring, and HUD batching |
| Render submission | <= 5 ms/frame CPU side (road projection, streamer, traffic, particles, effects) |
| GPU | <= 8 ms/frame (SceneKit render, bloom/post, particles, skyline, grid) |
| Scene complexity | <= 650 active recursive nodes and <= 420 geometry/draw-ish nodes in medium tier |
| Road/props | 14 road chunks; streamed props/traffic only inside the tier draw distance |
| Memory | < 650 MB resident after load; no sustained growth over three race/retry loops |
| Transient allocation | < 5 MB/s during races; no per-frame texture/image allocation |
| Load time | Title-to-race interactive in < 3 seconds |
| Thermal | No escalation beyond `.fair` during a representative run; `.serious`/`.critical` forces low-tier cosmetics |

## Procedure

Run from a **clean clone** so no local artifacts contaminate the build.

### 1. Clean clone and archive

```sh
git clone https://github.com/rwrife/neon-racer.git
cd neon-racer
git status --short            # must print nothing
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
sudo xcode-select -s "$DEVELOPER_DIR"
VERSION=1.0
BUILD_NUMBER=42               # next monotonic build number
xcodebuild archive \
  -project NeonRacer.xcodeproj \
  -scheme NeonRacer \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/NeonRacer.xcarchive" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
```

Install the resulting Release build onto the physical device with the owner
signing account. Do not profile a Debug or Simulator build for this gate.

### 2. Device run

1. Disable Low Power Mode, reboot the device, let it cool to nominal, and
   disconnect other debug sessions.
2. Cold-launch the app, complete one warm-up race, then measure a full race
   plus two immediate retries on a representative route.
3. Repeat the same run in Low, Medium, and High settings. Confirm the score
   trace and final outcome match for the same input and seed.

### 3. Instrument with Instruments

- **Time Profiler** for `RaceSimulation.advance`, road projection, streamer
  updates, and HUD publication (CPU simulation + render submission).
- **Metal System Trace / Core Animation** for SceneKit frame pacing, overdraw,
  and render-target scale (GPU + frame pacing).
- **Allocations / Leaks** for the three-race retry loop and stage transitions
  (memory + transient allocation).
- **Energy Log** for thermal behavior over repeated runs (thermal).

Record p95 frame time, CPU simulation, render submission, GPU time, live node
count, resident memory, transient allocation rate, title-to-race load time,
thermal state, device model, iOS version, and route.

### 4. Record the result

Copy the measured values into `docs/performance-device-evidence.md`, set
`SIGN_OFF_DATE` to the measurement date, and fill every metric cell. Leave no
`PENDING` cell. Save `.trace` files outside source control.

### 5. Verify the gate

```sh
bash scripts/check_device_signoff.sh && echo "release gate: PASS"
```

The gate exits non-zero until a dated, fully-filled evidence record exists.

## Not done here

This file documents the gate and procedure. The measurement itself is an owner
device run; until it happens, `docs/performance-device-evidence.md` stays
`PENDING` and the gate keeps failing closed.
