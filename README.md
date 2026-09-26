# Neon Racer

Neon Racer is an original native iOS arcade racing game with a retro-futurist neon visual style.

## Requirements

- Xcode 26 or later
- iOS 26 or later
- Swift 6

The app is iPhone-only and runs in landscape orientation.

## Architecture

- `App`: SwiftUI application lifecycle and top-level navigation.
- `Features`: SwiftUI screens such as the main menu and race container.
- `Game`: Frame-rate-independent simulation and SpriteKit rendering. This layer does not import SwiftUI.
- `Content`: Codable stage and palette definitions.
- `Services`: Audio, haptics, and persistence boundaries.
- `Shared`: Cross-cutting design tokens and diagnostics.

The gameplay simulation uses a fixed timestep, seeded randomness, explicit player commands, bounded catch-up, pause/restart semantics, and immutable interpolated render snapshots. Rendering is handled separately by `RaceScene`, so core tests run without SpriteKit.

## Build and run

1. Open `NeonRacer.xcodeproj` in Xcode 26 or later.
2. Select the `NeonRacer` scheme.
3. Choose an iOS 26 iPhone simulator.
4. Build and run.

The placeholder main menu launches an animated SpriteKit scene that validates the app shell, fixed-step simulation, and native rendering integration.

## Tests

Run the `NeonRacer` scheme tests in Xcode or from macOS:

```sh
xcodebuild test \
  -project NeonRacer.xcodeproj \
  -scheme NeonRacer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Adding content

Add stage definitions under `NeonRacer/Content` and visual assets under `NeonRacer/Resources/Assets.xcassets`. Stage content should be decoded into typed `Codable` models and validated before a race begins. Avoid raw dictionaries and runtime string lookups in gameplay systems.

All shipped art, fonts, music, and sound effects must be original or have documented redistribution rights.

