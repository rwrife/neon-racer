# Initial route theme content

`InitialRouteContent.bundle` is the typed, `Codable` fixture for the launch route
**Solar to Summit**. Its `StageContentDocument` uses the shared route, palette, traffic,
scenery, weather, music, difficulty, asset-manifest, and budget models. Theme-zone and
transition metadata layer renderer-facing assignments around that document without
coupling content to SpriteKit.

## Route structure

1. **Sunset Coast** opens on a causeway, passes the striped solar landmark, and exits
   through a banked cliff sweep.
2. **Neon City** raises traffic pressure through the rain gate and VANTA canyon.
3. The city gateway presents a labeled fork:
   - **Orbit Skyway** uses the AXIS tunnel and elevated deck before entering the peaks.
   - **Storm Pass** climbs directly into mist and sharper switchbacks.
4. Both branches reconnect at **Summit Finish**, using the relay ridge and summit run.

Every complete path therefore visits Sunset Coast, Neon City, and Midnight Peaks.
Validation checks that all nodes are reachable, every reachable node can finish, both
branches reconnect, and each path contains all three themes.

## Renderer and systems contract

- `stage.route.sections` supplies ordered length, curve, elevation, lane, and link values.
- `themeZones` assigns shared palette, traffic, scenery, weather, and music definitions
  to road sections.
- `proceduralPlaceholders` describes original primitive instructions corresponding to
  every manifest entry. No image, model, font, sample, or third-party art is required.
- Traffic profiles cap density and vehicles while retaining at least 1.25 seconds of
  headway.
- Weather profiles retain at least 65% visibility and 75% road grip.
- Music cues name original procedural arrangements and transition crossfade timing.
- `transitions` defines preload distance and independent palette, scenery, and music
  blends for each route edge.

## Remaining integration work

The fixture intentionally does not implement renderer or progression behavior. The
environment renderer must map scenery primitives to original generated geometry, render
surface/reflection roles, and accessibility-gate mist, rain, aurora, and storm cues.
The route system must consume node edges, present fork labels/shapes, stream the target
theme at `preloadDistance`, and apply section geometry. The audio system must map cue IDs
to procedural synthesis arrangements and perform timed crossfades.

Screenshot/reference capture remains blocked until those systems render authored content.
When available, capture both branches in default, high-contrast, color-vision-safe,
Reduce Motion, and Reduce Effects modes using the checklist in `VisualStyleGuide.md`.

### Axis tunnel

The `city-axis-tunnel` section contains a physical tunnel from 120 to 600 meters.
The Skyline Run's middle section uses the same partial-section treatment. The
road mesh, physics, curvature, and elevation continue unchanged through open
portals. Opaque walls/ceiling, neon rails, overhead strips, and wall signs stream
in before the entrance; external roadside props are omitted inside the shell.
The chase camera lowers over the 60 meters before entry and returns to its normal
height after its trailing position has cleared the exit. Lights remain steady to
avoid introducing flashing. `testTunnelInterior` captures the authored tunnel on
a short Debug-only route for visual review.

### Split lanes and reconnection

Coast Solar Sweep splits into a three-lane left branch and a two-lane right
branch. Skyline Run's first section offers three lanes or one lane. Each split
starts 20% into its section, eases apart over 12% of the section, begins merging
at 70%, and is back to a three-lane road at 82%, before the next checkpoint.
Overhead lane-count signs announce the choice. Both paths are real asphalt
ribbons in the same world; steering chooses the path without changing scenes.
The median is off-road, traffic follows the actual branch lane centers, and
rivals cannot weave across the median. The road and camera remain continuous
through the split and merge. `testSplitRoadChoice` provides a Debug-only visual
capture of the authored split.

The split branches now follow separate paths: the wide coast road sweeps left
around a terrain island, while the narrow ridge bypass follows an independent
S bend and rises up to five meters. Their centerlines separate by more than 75
meters. Each path has its own tangent, elevation, road edges, and shoulders;
no road platform or grid spans the gap. Steering at the entrance chooses a path
for that split. Driving then uses the chosen road's local width and curvature,
and the chase camera follows its tangent. Both paths ease back into the same
three-lane road with matching position and heading at the merge.
