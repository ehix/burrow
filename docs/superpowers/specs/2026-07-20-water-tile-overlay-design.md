# Water Tile Visual Overlay (Design)

## 1. Goal

Give flooded tiles (`WaterIngress` hazard, `Level.set_water_at()`) a
textured, subtly-animated look instead of the current flat-color
`WATER_MARKER_COLOR` polygon fill — a saturated "wet floor" base with a
semi-transparent water surface drifting on top, following the same
`draw_texture_rect`/tinted-texture idiom this worktree already established
for `FloorRenderer` and `MazeRenderer` (`9205bbc`).

Purely visual. No gameplay effect, no change to flood/drain timing or
radius.

## 2. Non-goals

- No change to `WaterIngress`'s ring-based flood/drain logic, `RING_STEP`,
  or `FLOOD_RADIUS` — this only changes what a flooded tile looks like, not
  when tiles flood or drain.
- No cross-tile flood-edge blending. Each flooded tile's visual is an
  independent per-tile node, same as today's marker; adjacent wet/dry tiles
  may show a faint seam at the boundary. Acceptable for a first pass —
  revisit only if it reads badly in playtest.
- No gameplay hazard behavior (slowing the player, muffling sound, etc.) —
  confirmed out of scope for this iteration.
- Scroll speed/direction and overlay alpha are tuning constants, not locked
  by this spec — same "tune during playtest" posture as `RING_STEP`.

## 3. Assets

Two SpriteCook-generated textures, already reviewed:

- **Wet floor base** (SpriteCook asset `167258df-a3ef-4e7a-b9bc-b391a113825c`,
  314×314): murky reddish-brown clay floodwater, subtle even ripples, dull
  sheen. Saved as `assets/textures/wet_floor_material.png`.
- **Water overlay** (SpriteCook asset `2bd08a56-f480-4296-b8f8-5c83af7210b7`,
  222×215): greenish-brown floodwater with sharp, small-scale specular
  highlights forming a shimmering caustic pattern. Saved as
  `assets/textures/water_overlay_material.png`.

Both get verified seamless via the same headless-Godot 3×3 tile composite
check used for every prior texture in this worktree (`c0eec47`,
`b307cb5`), before being wired into any rendering code. `water_overlay` is
currently non-square (222×215) — if the 3×3 check shows a seam on either
axis, that's a regen request back to SpriteCook, not something to force
through.

The existing `assets/textures/water_material.png` (plain blue `#2673BF`,
committed in `b307cb5`, never referenced by any code) is deleted — these
two textures supersede its role with a palette that actually matches the
flood hazard's murky aesthetic.

## 4. Rendering mechanics

Flooded tiles already get a per-tile node spawned/freed by
`Level.set_water_at()` → `_spawn_water_marker()` / `queue_free()` — that
lifecycle is unchanged. What changes is what that node draws.

**Base layer** — the existing marker `Polygon2D` gets
`.texture = wet_floor_material.png` instead of a flat `WATER_MARKER_COLOR`
fill. Since the polygon is exactly one tile's bounds, Godot maps the
texture directly to the polygon's UVs — no tiling/repeat setup needed
(unlike `FloorRenderer`'s multi-tile `draw_texture_rect(tile=true)` case).
It keeps using `_ground_layer.dim_material()` exactly as today; per
`ground_dim.gdshader`'s own doc comment, the shader reads the built-in
`COLOR` (texture-sample × vertex-color, whichever applies), so giving the
polygon a real texture instead of a flat fill requires no shader change.

**Overlay layer** — a new child `Polygon2D`, sized to the same tile bounds,
`.texture = water_overlay_material.png`, alpha ≈0.7 (tune during
playtest) so the wet floor base shows through. This layer needs to
animate, so it cannot reuse `dim_material()` as-is:

- New shader `assets/shaders/water_overlay.gdshader`, `canvas_item` type.
  Samples `texture(TEXTURE, UV + TIME * scroll_speed)` for the drifting
  look, then applies the *same* desaturate/darken logic as
  `ground_dim.gdshader` (duplicated, not shared — see below) so it responds
  to the ceiling/ground focus toggle the same way the rest of the
  background layer does. No early `return` in `fragment()`, per this
  project's established shader constraint (`outline.gdshader`,
  `ground_dim.gdshader`).
- **Why a second material, not the shared one:** `GroundLayer`
  (`world/ground_layer.gd`) deliberately gives every ground-resident node
  the *same* `ShaderMaterial` instance, specifically so one
  `set_dimmed()` call darkens the whole background layer together (a
  documented `CanvasGroup` alternative silently dropped late-added
  children — see that file's doc comment). An animated shader needs its
  own `TIME`-driven uniform state that the shared instance can't carry
  without affecting every other ground child's texture sampling. So
  `GroundLayer` gains a second accessor, `water_overlay_material()`,
  backed by its own `ShaderMaterial`/`water_overlay.gdshader` instance.
  `GroundLayer.set_dimmed()` is updated to set `dim_enabled` on *both*
  materials, keeping the "whole layer dims together" guarantee intact for
  callers — they still only ever call `set_dimmed()` once.

## 5. Testing

- Extend or add a test alongside the existing `tests/test_ground_layer.gd`
  / water-hazard tests confirming: a flooded tile's marker node carries the
  wet-floor texture; the overlay child exists and uses
  `GroundLayer.water_overlay_material()`; `set_dimmed()` toggles
  `dim_enabled` on both materials.
- Manual verification: headless Godot boot, trigger a `WaterIngress` flood
  in a running scene, screenshot before/after to confirm the two-layer
  look renders and the overlay visibly drifts over a couple of seconds.
