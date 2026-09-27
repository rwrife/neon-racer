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
