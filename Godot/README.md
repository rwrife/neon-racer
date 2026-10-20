# Neon Racer - Godot application

This is a functional, experimental side-by-side port, **not yet a near-pixel-perfect
replacement** for the Swift application. The existing Xcode project is unchanged.

## Run

Use **Godot 4.7.2 standard**, not the .NET editor. Import `project.godot` and press
F6 on `scenes/main.tscn`, or run from the repository root:

```sh
godot --path Godot
```

The game includes title, garage, vehicle previews, palette/route customization,
records, settings, accessibility preferences, a first-run driving guide, racing,
pause/confirmation dialogs, results, progression unlocks, damaged-profile recovery,
and interrupted-run recovery. All screens and controls are Godot-rendered; the same
implementation is intended for desktop and iOS. It does not embed SwiftUI.

Drive with **A/D** or the arrows, **W/up** for throttle, **S/down** for brake,
**Space** for boost, and **Escape/P** for pause. Gamepads use the left stick,
right/left triggers, A for boost, and Start for pause. Menus support focus navigation,
confirm, and cancel. Remapping any keyboard action disables the default WASD/P aliases,
matching the native application's remapping policy.

The on-screen steering pad and hold buttons handle independent touch IDs, drag
updates, cancellations, and focus loss. Boost also applies throttle. Labeled
focusable controls provide a hold/release alternative to touch gestures.
Landscape safe-area margins are applied on mobile.
The canvas expands with the window's aspect ratio instead of letterboxing;
menus, HUD, and touch targets follow the resized viewport with uniform scaling.

RACE opens a course-selection screen. Choose the tunnel or peaks itinerary before
starting Neon Loop; other routes show their fixed itinerary. A preparation screen
builds the entire selected course and actor pools before the countdown begins.
Restart/retry and interrupted-run recovery preserve that course. Steering cannot
change the itinerary at a checkpoint; the physical split-lane roads still allow
either branch while driving.

## Implementation

| Component | Responsibility |
| --- | --- |
| `scripts/main.gd` | Shared screens, navigation, lifecycle, input bindings, recovery |
| `scripts/simulation.gd` | Bounded 120 Hz simulation, driving, drifting, boost, scoring, locked course progression, traffic/collisions |
| `scripts/track.gd` | Native-exported road profiles, smooth curves/elevation, physical split paths, world mapping |
| `scripts/world.gd` | Road/terrain meshes, themed scenery, tunnels, camera, vehicle rendering |
| `scripts/car.gd` | Native roadster contour lights, wheel halos, responsive exhaust/underglow, boost trails and vehicle animation |
| `scripts/driving_controls.gd`, `scripts/hud.gd` | Shared touch controls and custom-drawn arcade HUD |
| `scripts/audio.gd` | Menu soundtrack, adaptive procedural stems, vehicle layers, ambience and cues |
| `scripts/profile_store.gd` | Versioned, validated local profiles and atomic JSON writes |

Roads use road-local markings, separate asphalt/shoulders, and the same branch
frames as vehicles. Road, terrain, and roadside visibility is bounded around the
player so distant stages cannot blanket the current road. Split-road obstacles
spawn on actual lanes; collision boxes use the rendered actors' meter-scale
positions rather than a fixed fraction of the entire split envelope.

The route graph is resolved once from the pre-race choices. All road, terrain,
tunnels, gantries, buildings, and background actors are constructed during
preparation and remain resident until leaving the race. Traffic and obstacles
reuse fixed renderer pools. During racing, nearby chunk visibility changes, but
no level chunks are built, replaced, or freed. This trades a longer preparation
step and higher resident memory for a stable, predetermined course. Checkpoints
cannot replace a visible tunnel with another route.
The chase camera uses road-local yaw without snapping to stage pitch changes,
road widths taper and lane markings crossfade over a 120-meter presentation
transition, and the sun, horizon, and fog blend between environments over three
seconds. The exported native driving samples remain unchanged.

City and coastal skylines use emissive window grids, colored facade strips,
contour lighting, and animated neon billboards. Denser city blocks include
illuminated rooftop searchlights and flying background traffic. All motion uses
the paused race clock and prebuilt nodes; no scenery is spawned while driving.
Reduced Motion freezes background movement and scrolling display patterns.
Reduced Flashes also disables neon brightness pulses.

Vehicle lighting includes native-positioned canopy and shoulder contours, side
skirts, wheel halos, a splitter and rear diffuser, brake-responsive taillights,
twin exhaust jets, and a soft underglow pool. Boost strengthens the lights and
exhaust and emits bounded world-space particle trails. Pausing freezes those
trails; reduced motion/flashes remove animation, flicker, and moving trails.

Crash recovery follows the native severity-based duration, initial slowdown,
sideways slide, airborne spin/roll, landing bounce, and stationary branch-center
respawn with a shield. Reduced Motion disables the spin/roll and limits lift.

Off-asphalt steering toward the road retains a minimum response even at a
standstill or against outward cornering forces. This intentionally extends the
native driving behavior to prevent off-road drag from trapping the car. Recovery
works on shoulders and both sides of each split branch without auto-centering;
normal on-road handling and off-road speed penalties remain unchanged.

The title art, icon, menu soundtrack, and roadster source are copies of existing
repository assets. `assets/roadster-colored.res` preserves the OBJ's vertex colors,
normals, and geometry; standard OBJ import did not preserve the required baked
shading. `shaders/paint.gdshader` uses the native luminance-based recoloring rule.
The scanline/chromatic post-process is translated from `NeonPostProcess.metal`.

`assets/swift-reference.json` is generated by compiling the actual Swift core.
It includes all three routes for all three difficulty/vehicle profiles, native
procedural road shapes, driving cases, and physical-split samples. Native code is
not needed at runtime. Regenerate it after changing the Swift reference:

```sh
bash scripts/export_godot_reference.sh
godot --headless --path Godot --script res://tools/import_roadster.gd
godot --headless --path Godot --script res://tools/bake_audio.gd
```

The second and third commands only need rerunning after changing the roadster or
the procedural audio port. The audio baker translates the native synth equations
into 22.05 kHz mono PCM resources; the native engine uses stereo-identical samples.
It is not a bit-exact replacement for AVAudioEngine: noise generators, sample rate,
filters, limiting, mixing transitions, and platform audio-session behavior differ.

Profiles use Godot's `user://` application directory. This port has a separate save
schema and does **not** import an installed Swift application's saves. Corrupt
profiles require an explicit reset and are preserved in a timestamped backup.
Recovery restarts the interrupted route/loadout, not the exact mid-race simulation.
Resetting player data preserves audio/accessibility preferences.

## Checks and captures

Run all checks, including the exported content pack:

```sh
bash scripts/test_godot.sh
```

Set `GODOT=/absolute/path/to/Godot` if the editor is not on `PATH`. Individual checks:

```sh
godot --headless --path Godot --editor --import
godot --headless --path Godot --script res://tests/run_tests.gd
godot --headless --path Godot --script res://tests/smoke_ui.gd
```

Core checks compare driving and split geometry against Swift-generated values,
exercise fixed-step/pause/boost/scoring/persistence behavior, and complete all three
routes with a collision-free assisted driver. UI checks navigate screens, exercise
simultaneous touches, load/mix/mute the sound bank, and verify cleanup. Regressions
also cover split-road mesh/vehicle alignment, collision widths and obstacle lanes,
bounded terrain visibility, airborne crash poses, and branch-preserving respawns.
Off-road regressions exercise stationary, braking, uphill, boosted, and curved
recovery across all vehicle profiles, plus both edges of both physical split roads.
Actual checkpoint crossings check both preselected itineraries, retained tunnels,
constant node/mesh identities, no in-race construction, camera continuity, gradual
environment changes, preallocated actor pools, and accessibility-aware neon effects.
Window-resize checks cover tall, wide, and compact aspect ratios and input targets.

Capture deterministic desktop reference screens in an existing output directory:

```sh
godot --path Godot --script res://tests/capture.gd -- /absolute/path/to/captures
```

Captures include course selection, both split branches, a tunnel, boost lighting,
the neon city, wide/square windows, before/during/after an environment-changing
checkpoint, a locked-course checkpoint, and airborne/landing/respawn crash
frames, and use an isolated test profile/recovery path. These are review artifacts,
not evidence of visual parity with the native application. The `Godot port` CI
workflow checks native-reference drift, runs source/content-pack tests, and builds
an ad-hoc-signed universal macOS application. It verifies the exported app's
signature and checks startup using its bundled runtime, without the editor.
Source and content-pack UI smoke checks run separately. Pull requests, relevant
pushes, and manual runs publish `godot-content-pack`
and `godot-macos` artifacts for 14 days. The macOS build is a development build,
not a notarized release; the content pack is not an iOS application.

To build the same macOS app locally, install the matching macOS export template:

```sh
mkdir -p Godot/exports/macos
godot --headless --path Godot --editor --import
godot --headless --path Godot --export-release macOS exports/macos/NeonRacerGodot.zip
```

## iOS

`export_presets.cfg` defines an **iPhone-only**, landscape, iOS 26+ project export.
It uses the development bundle ID `com.infinityball.neonracer.godot` so it cannot
replace the installed native app. The Apple team ID is deliberately blank.

1. Install matching **4.7.2 export templates** using the Godot template manager.
2. Use macOS with full Xcode selected through `DEVELOPER_DIR` or `xcode-select`.
3. In the iOS preset, enter the owner's Apple team ID and local signing settings.
4. Export to an empty directory under `exports/ios`, open the generated Xcode
   project, and build for a physical iPhone.
5. Check simultaneous touch, safe areas, suspend/resume, controller reconnect,
   silent-switch/audio interruptions, haptics, thermal behavior, and accessibility.

The Mobile renderer is intended for physical devices. Godot's iOS simulator
requires the Compatibility renderer, so simulator captures are not a substitute
for on-device rendering/performance signoff.

A content pack can be built without signing or export templates:

```sh
mkdir -p Godot/exports/ios
godot --headless --path Godot --export-pack iOS exports/ios/NeonRacerGodot.pck
```

This only verifies packaging; it does **not** create a runnable iOS application.
The initial development environment had neither the matching iOS template nor a
selected full Xcode installation, so no iOS binary or signing was verified.

## Fidelity and release limitations

Screens have functional equivalents, but native typography, sheet transitions,
garage presentation, HUD layout/minimap, vehicle animation, lighting, atmosphere,
terrain, scenery, weather, bloom, and effects are not pixel-matched. The road
profile/driving fixture checks do not establish whole-game simulation parity.

Traffic spawning/AI, obstacle variants, collision detection and crash recovery,
combo event cooldowns/deduplication, and scoring feedback are currently simplified
relative to the Swift systems. Deterministic Swift diagnostic replays and its
adaptive thermal/memory quality policy are not implemented in Godot.

Accessibility names/descriptions, focus handling, larger HUD, color palettes,
contrast, and reduced motion/flashes are provided, but iOS VoiceOver, system
Reduce Motion/Dynamic Type, and platform interruption/haptic behavior are not
signed off. Not all visual effects have equivalent accessibility treatment yet.

Do not submit this build as the native app's replacement. iOS export/signing,
privacy-manifest review for the Godot runtime, licenses/notices, asset rights,
device performance, accessibility, and same-device screenshot comparisons remain
release requirements. Existing asset-rights review requirements are inherited;
conversion does not clear an asset for distribution.
