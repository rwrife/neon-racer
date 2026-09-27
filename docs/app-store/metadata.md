# App Store metadata and release notes

The version 1.0 listing and screenshots live in [`AppStoreAssets`](../../AppStoreAssets/README.md). Use that listing as the source for App Store Connect.

All copy is draft text pending owner, product, IP, privacy, and App Review validation.

## Listing

- **Name:** CyberRun
- **Subtitle (30 characters max):** Neon arcade racing
- **Primary category:** Games
- **Secondary category:** Racing
- **Promotional text:** Race glowing routes, time your boosts, and chase a new personal best.
- **Keywords (100 characters max):** racing,arcade,neon,driving,speed,boost,drift,score,offline,car

### Description

See the final version 1.0 description in [`AppStoreAssets/listing.md`](../../AppStoreAssets/listing.md).

**Features**

- Immediate, touch-first arcade racing
- Original retro-futurist 3D neon presentation
- Fast restarts for score-chasing runs
- Local progress with no account required
- Adaptive race music and effects
- No ads, analytics, tracking, or data collection
- Offline play

Final copy must describe only features present in the submitted build.

## Required owner inputs

- **Support URL:** `[PUBLIC HTTPS SUPPORT URL]`
- **Privacy policy URL:** `[PUBLIC HTTPS PRIVACY URL]`
- **Marketing URL:** optional
- **Copyright:** `[YEAR] [LEGAL OWNER]`
- **Support email:** `[SUPPORT EMAIL]`

Do not submit placeholder values.

## Age rating and capabilities draft

Complete Apple's current questionnaire against the final content. Expected current inputs are no realistic violence, fear, sexual content, profanity, gambling, contests, alcohol/drugs, medical content, user-generated content, messaging, unrestricted web access, advertising, loot boxes, or external purchases. Reassess flashing visuals, collision effects, and any future story/audio content before submission.

- iPhone and iPad; landscape left and right.
- Internet connection and account are not required.
- Game controller: do not claim support until controller navigation and gameplay pass TestFlight testing.
- Accessibility: do not claim App Store accessibility features until each claimed feature is tested in the release build.

## Controller and accessibility notes

Store metadata should say touch input is supported. Controller support remains unclaimed unless smoke tests cover pairing, menu navigation, race control, pause/resume, disconnect/reconnect, and remapping expectations. Accessibility claims must be backed by release-build testing for VoiceOver labels/focus, Dynamic Type where applicable, contrast, reduced motion/flashes, and color-independent gameplay cues.

## Screenshot and preview plan

The current 6.5-inch iPhone and 13-inch iPad capture sets are in [`AppStoreAssets/screenshots`](../../AppStoreAssets/screenshots). Review the final signed build on both devices before upload.

Further optional captures could show:

1. Main menu/title and visual identity.
2. Clear gameplay view showing the course and vehicle.
3. High-intensity gameplay/effects.
4. Score/result or progression moment.
5. Settings/accessibility screen, if shipped.

Use lossless source captures from the release build with no device frame unless permitted. Do not composite unavailable features. Keep text inside safe areas and localize both UI and marketing copy. An app preview is optional; if produced, use only captured gameplay, cleared audio, and accurate touch/controller presentation.

## Launch and icon gate

The launch presentation uses the app target's generated launch screen (`INFOPLIST_KEY_UILaunchScreen_Generation = YES`) and must be checked on every supported size and orientation. The app icon is the original 1024×1024 RGB asset in `NeonRacer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`; validate in archive/export that it has no transparency and appears correctly in SpringBoard, Settings, TestFlight, and App Store Connect.
