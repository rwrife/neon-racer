# Asset provenance and IP review

Every shipped visual, font, music, sound, copy, and generated asset must be registered before release. Store source files and license evidence in an owner-controlled location; do not rely on a download URL remaining available.

## Current register

| Asset | Kind | Source/creator | Rights basis | Evidence | Status |
| --- | --- | --- | --- | --- | --- |
| `Assets.xcassets/AccentColor.colorset/Contents.json` | Color definition | Project authors | Original configuration | Git history | Cleared |
| `Assets.xcassets/AppIcon.appiconset/Contents.json` | Empty icon catalog definition | Project authors | Original configuration | Git history | **Blocked: final icon art absent** |
| Procedural vehicle definitions and animation in `VehicleArt.swift` | Runtime vector/primitive placeholder art | Project authors, 2026-09-26 | Original normalized polygon geometry; no source images, model generation, logos, or traced references | Git history, `VehicleArtPipeline.md`, and code review | Cleared as placeholder; final commissioned art and trade-dress review absent |
| SpriteKit road and effects drawn in `RaceScene.swift` | Runtime vector/primitive art | Project authors | Original code-generated art | Git history and code review | Provisional; final visual review required |
| SwiftUI interface copy and styling | UI/copy | Project authors | Original | Git history | Provisional; final copy review required |
| Procedural synthwave loop, engine tone, ambience/noise, and cues in `AudioService.swift` | Runtime-generated audio | Project authors | Original deterministic synthesis code; no recordings, samples, or third-party assets | Git history and code review | Cleared |
| Theme scenery instructions in `InitialRouteContent.swift` | Runtime primitive specifications | Project authors | Original procedural content definitions; no external art or media | Git history and code review | Cleared as placeholders; rendered output requires visual review |
| Future recorded music, SFX, images, and custom fonts | Media | None currently shipped | N/A | Resource audit | Add each file before shipping |

For generated assets, record the generator/model and version, prompt or source inputs, generation date, editor, post-processing, commercial-use terms, and evidence that inputs and outputs do not imitate protected characters, brands, or living artists.

## Per-asset intake checklist

- [ ] Stable asset path and human-readable title recorded.
- [ ] Creator/vendor and acquisition date recorded.
- [ ] Original work, commissioned assignment, or license permits commercial app distribution.
- [ ] License text, invoice, assignment, or generation record archived.
- [ ] Attribution requirements are satisfied in-app and in metadata.
- [ ] Modification, synchronization, and sublicensing restrictions reviewed.
- [ ] No trademark, trade dress, celebrity likeness, copyrighted character, or unlicensed sample.
- [ ] Font embedding and audio performance/mechanical rights confirmed where applicable.
- [ ] Source and exported asset contain no hidden personal or location metadata.
- [ ] Reviewer and review date recorded.

## Product IP checklist

- [ ] Search “Neon Racer” and proposed subtitle in relevant trademark classes and storefronts; owner/legal reviewer approves the name.
- [ ] App icon, logo, typography, UI, vehicles, routes, teams, sponsors, signage, and liveries are original and not confusingly similar to real products or racing properties.
- [ ] Fictional vehicle silhouettes do not reproduce distinctive protected designs.
- [ ] Route names/layouts do not imply affiliation with real venues or events.
- [ ] Audio contains no unlicensed recordings, samples, voices, or recognizable melodies.
- [ ] Marketing screenshots and preview footage contain only cleared in-app content.
- [ ] Store copy makes no unsupported claims and does not imply endorsement.
- [ ] Open-source notices and license obligations are complete.
- [ ] Legal owner approves the final binary and marketing package.
