# Content authoring

Stage files are UTF-8 JSON decoded into `StageContentDocument`. The shipped example is
`NeonRacer/Content/Fixtures/neon-harbor.json`. Copy it when starting a route or theme;
do not read JSON dictionaries from gameplay code.

## Versioning and migration

`schemaVersion` is required and is currently `1`. The app uses
`ContentMigrationPolicy.currentOnly`: it rejects older and newer files with a diagnostic
pointing at `schemaVersion`. A schema change must:

1. increment `StageContentDocument.currentSchemaVersion`;
2. document renamed, added, removed, or reinterpreted fields here;
3. update every bundled fixture and its tests in the same change; and
4. either provide a deterministic migration before opting into
   `migrateOlderVersions`, or intentionally retain `currentOnly`.

Silent defaults are not allowed for semantic fields. This keeps malformed or stale
content from changing race behavior unnoticed.

## Authoring a route

1. Give the stage and every section, checkpoint, fork, and lane change a lowercase
   kebab-case ID.
2. Set `startSectionID`, at least one `finishSectionIDs` value, and section `links`.
   Every section must be reachable from the start, every fork branch must reach a
   finish, and each fork destination needs a matching link carrying its `forkID`.
3. Express positions (`at`) in meters from the beginning of their section. Curve
   samples are normalized from `-1` (full left) to `1` (full right). Lane counts are
   1–8 and checkpoint `order` values must be unique and listed in ascending order.
4. Reference palette, traffic, scenery, weather, music, and difficulty definitions by
   ID. References never fall back to a default.
5. Keep route length, section count, traffic, and scenery under the declared budgets.

## Adding a theme

Add a palette, scenery profile, weather profile, and their assets. Colors use
`#RRGGBB` or `#RRGGBBAA`. Scenery bands define route-distance and lateral ranges,
spacing, placement side, and a hard instance cap. Add every image, audio, particle,
and vehicle resource to `assets.entries` with the correct `kind`, then use its asset ID
from content. Production loading should pass `BundleAssetResolver` so missing bundle
resources fail during development rather than during a race.

## Loading and diagnostics

Use `StageContentLoader.load(from:)` for files or `loadFixture(named:bundle:)` for a
bundled fixture. Loading performs decoding, reference, graph, ordering, range, asset,
and budget validation. A failure is `StageContentLoadError`; each
`ContentDiagnostic` includes the source path, precise field path, stable code, and
actionable message. Present all diagnostics together in authoring tools and fail fast
in debug builds.

The renderer and simulation should consume `StageContentDocument` and its typed child
models. Runtime wiring is intentionally separate from the schema so route/rendering
work can adopt the models without merge-sensitive scene changes.
