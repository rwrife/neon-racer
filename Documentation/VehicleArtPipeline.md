# Vehicle art pipeline

The current vehicles are original code-generated vector placeholders. They establish gameplay proportions, state behavior, and replacement contracts; they are not final production illustrations.

## Art direction and provenance

- Source: `NeonRacer/Game/Rendering/VehicleArt.swift`, authored for CyberRun on 2026-09-26.
- Method: hand-authored normalized polygon points rendered with SpriteKit primitives. No source images, generative model, external vehicle files, logos, type treatments, or traced reference pixels were used.
- Intent: broad fictional retro-future categories rather than identifiable makes or models. The player wedge, narrow coupe, tall hauler, and split-wing interceptor must remain distinguishable in a one-color silhouette.
- Review requirement: final replacement art needs an originality/trade-dress review and its own provenance row in `AssetProvenance.md`.

## Coordinate and layout contract

| Setting | Convention |
| --- | --- |
| Native frame | 384 × 256 px logical canvas |
| Working scale | Author at 3× (1152 × 768 px) when rasterizing |
| Coordinate space | Normalized 0…1, origin at lower-left |
| Anchor | Per-class normalized rear contact/axle point; player `(0.50, 0.18)` |
| Collision | Per-class normalized axis-aligned rectangle; never derive gameplay collision from transparent pixels |
| Safe padding | 12 px at native size, including glow and exhaust |
| Atlas | `vehicles@3x`, maximum 2048 × 2048, 4 px extrusion, 8 px inter-frame padding |
| Color | sRGB IEC61966-2.1, straight alpha source; premultiplied by SpriteKit at runtime |
| Filtering | Linear for native/high-density output; preserve a crisp non-glowing silhouette core |

Atlas frame names use lowercase dot-separated identifiers:

```text
vehicle.<class>.<state>.<phase>
vehicle.player-wedge.boost.01
vehicle.traffic-hauler.idle.00
```

Do not encode palette in geometry names. Palettes are applied as material variants: `electricDusk`, `hardSignal`, and `blueOrange`. A future raster exporter should emit a manifest containing canvas size, anchor, collision rectangle, palette, state, phase count, and source revision.

## Runtime state contract

`VehicleFrameSelector` chooses a state in this priority order:

1. damage
2. boost
3. brake
4. drift left/right
5. steer left/right
6. idle

Steering has separate enter/exit thresholds to prevent frame popping around center. Boost and damage use two 80 ms phases. Reduce Motion keeps semantic frame changes but removes body/cabin lateral animation and freezes exhaust length. `RaceScene` currently supplies steering, derived drift, brake, and boost. Damage is wired into the API but remains `0` until collision/durability simulation lands.

## Preview and replacement workflow

In a DEBUG race build, choose **VEHICLE SHEET** to open `VehicleArtPreviewScene`. It displays every class in every palette with anchor and collision overlays, plus the complete player state row.

When replacing procedural placeholders:

1. Preserve class identifiers, frame names, native canvas, anchor, and collision metadata.
2. Check silhouettes at 25% scale and in grayscale before adding color.
3. Check every state in all palette families, Reduce Motion, and reduced-effects mode.
4. Verify no frame shifts at a fixed anchor and no glow/exhaust crosses safe padding.
5. Archive layered sources and export logs in owner-controlled storage.
6. Add creator, date, tools, license/assignment, and reviewer to `AssetProvenance.md`.

## Known final-art gaps

- No final commissioned/approved hero or traffic illustration is present.
- No raster atlas or automated atlas exporter/manifest writer is present; runtime vectors are the reference implementation.
- Projected front/side traffic angles are not drawn because traffic projection is not yet integrated into `RaceScene`.
- Damage has a display state but no simulation event or damage severity feed.
- Exhaust, shadow, wheel detail, material texture, and per-frame cleanup remain placeholder quality.
- Device screenshot, grayscale, bloom, and trade-dress reviews are still required for final art.
