# Neon Racer

Neon Racer is an original native iOS arcade racing game with a retro-futurist neon visual style.

## Requirements

- Xcode 26 or later
- iOS 26 or later
- Swift 6

The app is iPhone-only and runs in landscape orientation.

CI pins Xcode 26.6 (`17F113`) and the iOS 26.5 simulator SDK on GitHub's
`macos-26` runner rather than following the runner's changing default Xcode.

## Architecture

- `App`: SwiftUI application lifecycle and top-level navigation.
- `Features`: SwiftUI screens such as the main menu and race container.
- `Game`: Frame-rate-independent simulation and SpriteKit rendering. This layer does not import SwiftUI.
- `Content`: Codable stage and palette definitions.
- `Services`: Audio, haptics, and persistence boundaries.
- `Shared`: Cross-cutting design tokens and diagnostics.

The gameplay simulation uses a fixed timestep, seeded randomness, explicit player commands, bounded catch-up, pause/restart semantics, and immutable interpolated render snapshots. Rendering is handled separately by `RaceScene`, so core tests run without SpriteKit.

Audio uses typed music, engine, tire, ambience, impact, UI, and voice buses. Its
mixing/lifecycle reducer and smoothed vehicle parameters are platform-independent and
unit tested; `AudioService` maps that state onto AVAudioEngine. The current soundscape is
generated entirely in code, so missing future resources never block gameplay. Music and
effects levels and mute choices persist independently in user defaults.

### Deterministic diagnostic replays

`RaceReplayRecorder` records the seed plus frame deltas and player commands. Adjacent identical frames are run-length encoded, and the `Codable` JSON representation uses compact keys (`v`, `s`, `r`, and optional `e`) so fixtures remain small. `RaceReplayExecutor` feeds that stream back through `RaceSimulation` and can verify the recorded deterministic event sequence.

This is a developer diagnostic format, not a user-facing or cinematic replay feature. The format is versioned; unsupported versions and malformed run data fail decoding. Debug reporting protocols and snapshots are compiled only under `#if DEBUG`, while recording and execution remain platform-independent so `swift test` can exercise them.

## Build and run

1. Open `NeonRacer.xcodeproj` in Xcode 26 or later.
2. Select the `NeonRacer` scheme.
3. Choose an iOS 26 iPhone simulator.
4. Build and run.

The placeholder main menu launches an animated SpriteKit scene that validates the app shell, fixed-step simulation, and native rendering integration.

When running in the iOS Simulator on macOS, enable **I/O > Keyboard > Connect
Hardware Keyboard**. Drive with **A/D** or the left/right arrows, accelerate
with **W** or the up arrow, brake with **S** or the down arrow, boost with
**Space**, and pause with **Escape**.

## Accessibility

The main menu includes persistent options for reduced motion, reduced flashes, high
contrast, a larger race display, and color-vision-safe palettes. The race renderer honors
both the in-game Reduce Motion choice and the system Reduce Motion setting. Text, symbols,
and lane markings supplement color cues, and SwiftUI interface text continues to scale
with Dynamic Type.

VoiceOver supports the current menus, settings, pause flow, and labeled race controls.
Real-time high-speed steering is not guaranteed with VoiceOver; the race screen provides
an equivalent overview, while pre-race guidance and pause controls remain accessible.

## Tests

Run the `NeonRacer` scheme tests in Xcode or from macOS:

```sh
xcodebuild test \
  -project NeonRacer.xcodeproj \
  -scheme NeonRacer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Performance budgets, quality tiers, and the physical-device Instruments procedure are
documented in [`Documentation/Performance.md`](Documentation/Performance.md).

The launch route's three typed themes, fork/reconnect graph, transition contract, and
renderer integration gaps are documented in
[`Documentation/RouteThemes.md`](Documentation/RouteThemes.md).

## Release readiness

- [Release/archive and signing runbook](docs/release.md)
- [Privacy manifest review and App Store privacy answers](docs/privacy.md)
- [Asset provenance and IP checklist](docs/provenance.md)
- [TestFlight smoke and rollback checklist](docs/testflight.md)
- [App Store metadata and screenshot draft](docs/app-store/metadata.md)

The project intentionally contains no signing secrets or team identifier. Owner approval
of the icon, public support/privacy URLs, legal-owner metadata, device testing, and
owner-approved signing remain release gates.

## Adding content

Add stage definitions under `NeonRacer/Content` and visual assets under `NeonRacer/Resources/Assets.xcassets`. Stage content is decoded into versioned typed `Codable` models and validated before a race begins. Avoid raw dictionaries and runtime string lookups in gameplay systems. See the [content authoring guide](Documentation/ContentAuthoring.md) for the schema, migration policy, route and theme workflow, validation rules, and fixture loader.

All shipped art, fonts, music, and sound effects must be original or have documented redistribution rights.

See the [visual style guide](Documentation/VisualStyleGuide.md) for the original-art policy, palette and readability rules, world language, accessibility constraints, target scene specifications, and screenshot review criteria used by vehicle, environment, HUD, VFX, and App Store asset work.
