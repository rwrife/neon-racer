# Asset provenance and IP review

Every shipped visual, font, music, sound, copy, generated asset, and marketing capture must be registered before release. Store source files and license evidence in an owner-controlled location; do not rely on a download URL remaining available.

## Current register

| Asset | Kind | Source/creator | Rights basis | Evidence | Status |
| --- | --- | --- | --- | --- | --- |
| `Assets.xcassets/AccentColor.colorset/Contents.json` | Color definition | Project authors | Original configuration | Git history | Cleared |
| `Assets.xcassets/AppIcon.appiconset/AppIcon.png` and `Contents.json` | Current app icon | Owner to verify | Owner to provide creation or license record | Icon replaced in commit `5fa6fdd` | Review required before submission |
| Procedural vehicle definitions and animation in app code | Runtime SceneKit/vector primitive art | Project authors | Original normalized primitive geometry; no source images, model imports, logos, or traced references | Git history, `Documentation/VehicleArtPipeline.md`, and code review | Cleared as placeholder; final trade-dress review still required |
| Route, road, scenery, lighting, and effects rendering | Runtime SceneKit/procedural geometry and materials | Project authors | Original code-generated art and parameters | Git history and visual review | Provisional; final screenshot/marketing review required |
| SwiftUI interface copy and styling | UI/copy | Project authors | Original | Git history | Provisional; final copy review required |
| Procedural synthwave loop, engine tone, ambience/noise, and cues | Runtime-generated audio | Project authors | Original deterministic synthesis code; no recordings, samples, voices, or third-party assets | Git history and code review | Cleared |
| Theme scenery instructions and route content | Runtime primitive specifications | Project authors | Original procedural content definitions; no external art or media | Git history and code review | Cleared as placeholders; rendered output requires visual review |
| `Resources/Assets.xcassets/TitleScreen.imageset/TitleScreen.jpg` | Title art | Owner to verify | Owner to provide creation or license record | Git history only | Review required before submission |
| `Resources/CyberpunkSpaceRace.mp3` | Menu soundtrack | Owner to verify | Owner to provide creation or license record and distribution rights | Introduced in commit `5fa6fdd` | Review required before submission |

For generated assets, record the generator/model and version, prompt or source inputs, generation date, editor, post-processing, commercial-use terms, and evidence that inputs and outputs do not imitate protected characters, brands, vehicles, venues, logos, living artists, or copyrighted styles.

## Per-asset intake checklist

- [ ] Stable asset path and human-readable title recorded.
- [ ] Creator/vendor and acquisition date recorded.
- [ ] Original work, commissioned assignment, or license permits commercial app distribution.
- [ ] License text, invoice, assignment, or generation record archived.
- [ ] Attribution requirements are satisfied in-app and in metadata.
- [ ] Modification, synchronization, sublicensing, storefront, and marketing restrictions reviewed.
- [ ] No trademark, trade dress, celebrity likeness, copyrighted character, venue, race series, or unlicensed sample.
- [ ] Font embedding and audio performance/mechanical rights confirmed where applicable.
- [ ] Source and exported asset contain no hidden personal or location metadata.
- [ ] Reviewer and review date recorded.

## Product IP checklist

- [ ] Search “CyberRun” and proposed subtitle in relevant trademark classes, app stores, game stores, domains, and social channels; owner/legal reviewer approves the name.
- [ ] App icon, logo, typography, UI, vehicles, routes, teams, sponsors, signage, and liveries are original and not confusingly similar to real products or racing properties.
- [ ] Fictional vehicle silhouettes do not reproduce distinctive protected designs.
- [ ] Route names/layouts do not imply affiliation with real venues, roads, events, cities, teams, or sponsors.
- [ ] Audio contains no unlicensed recordings, samples, voices, or recognizable melodies.
- [ ] Marketing screenshots and preview footage contain only cleared in-app content from the submitted build.
- [ ] Store copy makes no unsupported claims and does not imply endorsement by Apple, real brands, teams, or venues.
- [ ] Open-source notices and license obligations are complete.
- [ ] Privacy policy, support page, press kit, and website use the same cleared branding and claims.
- [ ] Legal owner approves the final binary and marketing package before submission.
