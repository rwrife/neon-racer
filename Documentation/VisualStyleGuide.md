# Neon Racer visual style guide

This guide is the visual contract for vehicles, environments, HUD, VFX, signage, and store captures. The direction is **electric dusk**: a dark, legible arcade road world built from broad silhouettes, sparse luminous edges, and warm/cool landmarks rather than a wall of glow.

## Originality and inspiration policy

The supplied visual reference is inspiration only; it is not a production asset or a composition to reproduce. Do not trace, paint over, sample colors or textures from, closely recreate, or include it in the asset catalog. Do not imitate a specific artist, franchise, logo, vehicle, type treatment, landmark, or advertisement.

Build mood boards from licensable references to general subjects (night roads, atmospheric optics, industrial materials, coastal weather) and record each source and intended lesson. Combine at least three unrelated observations into a new thumbnail, then change composition, proportions, details, palette, and fictional context. All production art must be original or have documented redistribution rights.

## Design principles

1. **Road first:** road edges, traffic, route choices, hazards, and HUD outrank scenery.
2. **Dark, not lost:** reserve near-black for depth while retaining large readable shapes.
3. **Glow has a source:** every halo surrounds a crisp luminous core; darkness separates accents.
4. **One visual sentence:** each scene has one dominant landmark, one palette story, and one motion effect.
5. **Shape plus color:** gameplay meaning never depends on hue alone.
6. **Future through fiction:** brands, places, vehicles, and symbols belong to Neon Racer's own world.

## Palette families

Hex values are sRGB starting points, not permission to flatten every scene to the same colors. `Ink` is the scene floor, `surface` is road/UI structure, and accents are role-based. White is reserved for critical information and specular cores.

| Family | Ink | Surface | Text/core | Cool/route | Hot/action | Warning | Use |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Electric dusk (default) | `#08051F` | `#19182C` | `#F7F4FF` | `#00E5F5` | `#FF2E88` | `#FFC857` | General play and marketing |
| Hard signal (high contrast) | `#030308` | `#11111B` | `#FFFFFF` | `#00FFFF` | `#FF3B9D` | `#FFD400` | High-contrast setting and small displays |
| Blue/orange (color-vision-safe) | `#071521` | `#102A3D` | `#F8FAFF` | `#43B3FF` | `#FF9F1C` | `#F6E652` | Deuteranopia/protanopia-safe alternative |

- Against each family ink, text/core is at least 17:1, cool accents at least 8:1, and hot/action accents at least 5.7:1. Recheck ratios after compositing, opacity, bloom, and color grading.
- Hazard red `#FF4D4D` is decorative unless paired with a warning shape, label, or pulse envelope. In the color-vision-safe family, use orange plus chevrons; never encode safe/danger as green/red alone.
- A stage may shift hue, but it must preserve these luminance roles. Never place cyan text directly on magenta glow or vice versa.

## Rendering language

### Contrast and black levels

- Body text and essential labels meet WCAG 2.2 contrast of 4.5:1; large text (at least 18 pt regular or 14 pt bold) meets 3:1.
- Road edges, hazards, route arrows, focus rings, and traffic silhouettes maintain 3:1 against immediately adjacent pixels in a paused gameplay capture.
- Use `#08051F` as the default black floor. Pure black is limited to letterbox/mask areas; shadow masses retain at least two distinguishable values on the target device.
- Keep a quiet dark gap between unrelated luminous elements. If bloom closes that gap, reduce bloom rather than brightening both objects.

### Gradients, emissive light, and effects

- Skies use two or three broad stops: darkest at zenith, a restrained saturated horizon band, and optional warm landmark light. Avoid rainbow ramps and visible banding.
- Emissive marks have a sharp core, a narrow colored halo, and optional faint atmospheric spill. The halo must not exceed twice the core width on each side or merge separate gameplay edges.
- Reserve maximum intensity for boost state, warnings, route confirmation, and primary calls to action. Ordinary scenery uses lower intensity and fewer simultaneous emitters.
- Chromatic separation is a brief impact/boost accent, never a continuous camera filter or a treatment for text.
- Scanlines are display texture, not world geometry: one device-pixel line every 3–4 output pixels, at no more than 8% opacity. Disable or reduce to 3% when it shimmers or competes with fine text.

### Grid, silhouettes, and depth

- Perspective grids share the road vanishing region. Lines compress and fade before the horizon; they do not pass through vehicles, labels, or solid scenery.
- Foreground silhouettes are broad and asymmetric, middle-distance shapes overlap in readable layers, and horizon detail is sparse.
- The player has a low, wide trapezoid; traffic uses narrower upright masses; hazards use triangular or alternating-chevron profiles. These categories remain distinct in grayscale and at thumbnail size.
- Use parallax, scale, occlusion, value, and atmospheric fade together. Do not communicate depth through blur alone.

### Typography and symbols

- HUD numerals use a sturdy tabular sans face; headings may use an extended geometric sans; body and accessibility text use the system sans. Use only original or properly licensed bundled fonts.
- Prefer uppercase for short labels only. Minimum rendered gameplay size is 17 pt equivalent, with semibold weight for text over motion.
- Do not outline paragraphs or apply glow directly to small glyphs. Put text on an opaque/dark scrim when the scene cannot maintain contrast.
- Fictional wordmarks use simple custom spacing and one memorable cut or notch, not an imitation of an existing logo. Icons have a solid silhouette and a redundant text, shape, or motion cue where meaning is critical.

## World language

### Vehicles

Vehicles are boxy retro-future machines: wedge cabin, strong shoulder line, clipped corners, visible wheel mass, and one signature light shape. Player cars are low and wide; traffic is taller and simpler. Limit each model to one primary body color, one dark material, and one emissive signature. Avoid recognizable real-world grilles, badges, liveries, and exact production-car proportions.

### Environments

- **Sunset Coast:** sweeping rock silhouettes, salt haze, low amber disc, sparse guardrails, and cool water reflections.
- **Neon City:** stacked service architecture, deep street canyons, elevated transit, window clusters, and controlled sign rhythm.
- **Midnight Peaks:** angular mountain cuts, cold moon, snow or mist bands, isolated relay structures, and long dark intervals.
- Tunnels use repeating structural bays and pools of light, not a uniform glowing tube. Weather changes depth and traction mood without obscuring road edges.
- Prop density rises near landmarks and intersections, then falls for recovery space. No more than one high-detail scenery cluster per screen region.

### Signage and branding

Use a fictional naming system built from short place/utility terms (for example, **VANTA PORT**, **AXIS RELAY**, **NOVA FUEL**) and a unique geometric mark. These examples are seeds, not mandatory final brands. Direction signs use consistent arrows, route numbers, border weights, and high-contrast panels. Ads may add flavor but never resemble real companies, obscure navigation, or use copyrighted slogans.

## Target scene sheets (written specifications)

Every eventual sheet must be an original composition with fictional branding and show a clean frame plus an effects frame. Annotate palette family, focal hierarchy, readability checks, and effects enabled.

| Target | Composition and identity | Gameplay read | Effect ceiling |
| --- | --- | --- | --- |
| Normal speed | Player centered low; road occupies lower half; one distant landmark and alternating quiet roadside clusters. | Both road edges visible; nearest three traffic silhouettes separate; speed and route HUD clear. | Low bloom; no chromatic split; sparse speed streaks. |
| Boost | Road narrows toward an offset landmark; player light signature stretches rearward without covering lanes. | Road-edge cores and traffic centers remain sharp; boost meter changes shape and label as well as color. | Streaks stay outside central hazard corridor; brief exposure lift, no whiteout. |
| Collision | Off-center impact with open recovery direction; debris follows the struck surface, not the HUD plane. | Player, obstacle, and safe exit remain identifiable in the impact frame. | One short flash, localized sparks, bounded shake; no full-screen red veil. |
| Route fork | Y-junction fills middle third; two distinct original landmarks and numbered arrow gantries identify branches. | Choice arrows appear before geometry divides; branch status uses label, arrow shape, and color. | Suppress decorative signs and streaks until choice resolves. |
| Tunnel | Dark portal frames a sequence of asymmetric service bays and an original **AXIS RELAY** marker. | Edge reflectors alternate by side; traffic reads against lit bays and dark gaps. | No continuous strobe; bloom falls between fixtures. |
| City | Elevated road bends past stacked blocks toward a single tower; fictional **VANTA PORT** signs cluster away from apex. | Apex, traffic, and navigation sign dominate advertisements; skyline stays below HUD contrast. | Limit animated signs to one region; reflections are dimmer than their sources. |
| Coast | Road traces a cliff with water on one side, broad rock mass on the other, and an original solar marker. | Guardrail and outer road edge separate from horizon; warm sun does not sit behind warning text. | Haze softens distance only; water glints do not flicker continuously. |
| Mountain | S-curve crosses layered angular ridges toward a relay beacon under a cold moon. | Snow/mist never erases both edges; chevrons reveal curve direction in grayscale. | Fog opacity leaves 3:1 critical-edge contrast; lightning, if used, is accessibility-gated. |

## Accessibility effect constraints

- Provide high-contrast and blue/orange palettes as complete presets, not post-process tints. Pair route, hazard, boost, and status colors with shapes and labels.
- **Reduce Motion:** remove camera shake, horizon roll, lateral parallax exaggeration, persistent speed lines, and chromatic separation; use short opacity/scale feedback instead.
- **Reduce Flash:** no more than three flashes in any one-second period, no alternating saturated full-screen fields, and no full-screen luminance flash. Replace lightning and collision flashes with localized glows.
- **Reduce Effects:** disable scanlines and film noise, halve bloom radius and particle count, remove chromatic separation, and retain crisp source geometry.
- Effects cannot cover HUD text, route arrows, the player silhouette, road edges, or the central traffic corridor. Accessibility settings apply to gameplay, menus, replays, and captures generated in app.

## Screenshot review

Review representative gameplay at native scale in default, high-contrast, blue/orange, Reduce Motion, and Reduce Effects configurations.

- [ ] At 100% scale, required text meets 4.5:1 (large text 3:1), and critical non-text elements meet 3:1.
- [ ] In grayscale, player, traffic, hazards, both road edges, and route choices remain distinguishable by shape/value.
- [ ] At 25% thumbnail size, the player, road direction, one focal landmark, and primary HUD message are still identifiable.
- [ ] Bloom preserves a crisp core, stays within the stated width ceiling, and does not join separate lanes, glyphs, or silhouettes.
- [ ] A frame histogram retains shadow separation and highlight detail; large areas are neither crushed pure black nor clipped white.
- [ ] Scanlines do not shimmer in motion or break glyphs; gradients show no obvious banding on the minimum target device.
- [ ] Boost, collision, and weather frames meet the effect constraints and remain readable in a paused worst-case frame.
- [ ] All visible vehicles, marks, signs, copy, and compositions are original or have recorded rights; no supplied reference pixels are present.
- [ ] App Store captures show authentic gameplay, safe-area clearance, consistent fiction, and no debug overlays or unlicensed content.

## Common failure modes

| Failure | Correction |
| --- | --- |
| Bloom turns the frame into colored fog | Restore the crisp source, narrow the halo, and darken adjacent decoration. |
| Blacks crush scenery and traffic together | Raise secondary silhouettes one value step; keep the ink floor stable. |
| Cyan and magenta overlap becomes illegible | Insert a dark separator or neutral scrim; change one element's role/value. |
| Every object glows | Remove emission from supporting props and reserve it for hierarchy. |
| Grid or scanlines create visual noise | Fade the grid before the horizon; lower density/opacity or disable texture. |
| Speed effects hide hazards | Clear the central corridor and cap streak length/opacity. |
| Color alone communicates state | Add a distinct icon, edge pattern, label, or animation envelope. |
| Fiction resembles a known brand or vehicle | Redesign the silhouette, proportions, lettering, mark, and context. |
| Scene reads as a generic neon collage | Reassert one landmark, one material/weather story, and quiet negative space. |

## Production references

Apply this guide when implementing [vehicles (#13)](https://github.com/rwrife/neon-racer/issues/13), [environments (#12)](https://github.com/rwrife/neon-racer/issues/12), [stage themes (#15)](https://github.com/rwrife/neon-racer/issues/15), [HUD (#16)](https://github.com/rwrife/neon-racer/issues/16), [VFX (#14)](https://github.com/rwrife/neon-racer/issues/14), [accessibility (#21)](https://github.com/rwrife/neon-racer/issues/21), and [App Store assets (#26)](https://github.com/rwrife/neon-racer/issues/26). Rendering tokens should ultimately map to typed palette content and shared design tokens rather than one-off colors in scene code.
