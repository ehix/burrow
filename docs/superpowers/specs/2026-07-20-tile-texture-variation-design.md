# Per-Tile Texture Variation (Design)

## 1. Goal

Fix a rendering defect found while playtesting the water-tile overlay work:
every floor tile, every wall tile, and every water tile currently shows the
*pixel-identical* crop of its source texture, because `FloorRenderer`,
`MazeRenderer`, `WallOverdrawMask`, and `WaterTileLayer` each draw a tile as
its own independent `draw_texture_rect(texture, rect, tile=true, ...)`
call, and Godot resets UV sampling to the rect's own origin on every call.
Confirmed empirically (a throwaway scratch scene drawing four adjacent
`draw_texture_rect(tile=true)` calls produced four bit-identical tiles, not
a coarse repeat — see this design's own review trail for the capture).

This design replaces that per-call reset with a per-tile-*coordinate*
pseudo-random crop of the source texture, so adjacent tiles genuinely show
different content instead of an obvious verbatim repeat.

## 2. Non-goals

- Wall decals (`assets/decals/root_tangle.png`,
  `assets/decals/crack_mineral_stain.png`) — generated for exactly this
  kind of wall variety but never wired into `WallOverdrawMask`. Explicitly
  deferred to a separate follow-up; this design only touches the base
  texture sampling, not decal stamping.
- Any new texture generation. All four affected textures
  (`wall_material.png` 80×71, `floor_material.png` 224×226,
  `wet_floor_material.png` 314×314, `water_overlay_material.png` 222×215)
  are already comfortably larger than the biggest single tile-sized draw
  used against them (48×48 at most), so there's enough valid crop range
  without generating anything new.
- True rotation (`transpose`). Dropped after review: none of
  `MazeRenderer`'s wall destination rects are square (front face and
  overdraw band are 48×16, top face is 48×32), and `transpose`-ing a
  non-square rect visibly squashes the sampled content. Flip (horizontal/
  vertical mirror) is always distortion-free regardless of rect shape, so
  the variant scheme uses flip only.
- Any change to `WaterIngress`'s flood/drain timing, or to the water
  overlay shader's `TIME`-scroll speed/behavior itself — this only changes
  *which* source-texture region each tile's draws sample from, not how the
  overlay animates once sampling.

## 3. Root cause (verified)

`draw_texture_rect(texture, rect, tile=true, modulate)`'s `tile` flag
makes Godot repeat the texture at native resolution *within* that one
rect — but the UV origin for that repeat is always the rect's own local
(0,0), never tied to the rect's position in world/canvas space. Since
`FloorRenderer`, `MazeRenderer`'s three per-wall-tile draws (own top face,
front face, overdraw band), and `WallOverdrawMask`'s repaint all issue one
independent `draw_texture_rect` call per tile with the *same* rect
dimensions each time, every tile ends up sampling the identical top-left
corner of the source texture.

## 4. Fix: `TileTextureVariant`

A new small pure-function module,
`world/maze/tile_texture_variant.gd` (`class_name TileTextureVariant`),
with one entry point:

```
static func draw_varied(canvas_item: CanvasItem, texture: Texture2D, dest_rect: Rect2, tile: Vector2i, modulate: Color = Color.WHITE) -> void
```

Internally:
1. Derives a deterministic hash from `tile` (Godot's built-in `hash()` on
   a `Vector2i` — no time/frame dependence, so a given tile always renders
   the same way, and `queue_redraw()` never causes visible jitter).
2. Picks a crop offset `(offset_x, offset_y)` within
   `[0, texture_size - dest_rect.size]` on each axis (clamped to `0` if
   the texture is smaller than the dest size on that axis — defensive,
   not expected to trigger given current textures), using distinct
   divisor/modulo steps on the hash per axis so x and y offsets aren't
   correlated.
3. Picks `flip_h`/`flip_v` from further bits of the same hash.
4. Issues `canvas_item.draw_texture_rect_region(texture, dest_rect_or_transformed, src_rect, modulate)`.
   **Superseded by commit `d00c4ec`:** the original design here flipped via
   a negative-size `dest_rect` (the standard Godot idiom) — this rendered
   broken on this project's actual runtime (GL Compatibility / Mesa d3d12
   on WSL2), silently ignoring the rect's sign and shifting a flipped tile
   onto a neighboring cell instead of mirroring it in place, leaving gaps
   that read as solid black across roughly half the map. Found by the
   implementation plan's manual visual validation step, not by this
   design's own reasoning. The shipped fix flips via
   `CanvasItem.draw_set_transform()` (scale `-1` on the flipped axis)
   around an always-positive-size `dest_rect` instead — see
   `world/maze/tile_texture_variant.gd`'s own doc comment for the actual
   mechanism and verification evidence.

This replaces `draw_texture_rect(..., tile=true, ...)` at every call site
below — `tile=true` is no longer used anywhere after this change.

## 5. Per-file integration

- **`world/maze/floor_renderer.gd`**: its one draw call becomes
  `TileTextureVariant.draw_varied(self, _floor_texture, rect, Vector2i(x, y), tint)`.
- **`world/maze/maze_renderer.gd`**: all three wall draws (own top face,
  front face, overdraw band) in `_draw_wall_ground`/`_draw_wall_ceiling`
  switch the same way, each keyed by that wall tile's own coordinate —
  the *same* tile key drives all three, so a given wall tile's top face,
  front face, and overdraw band show visually-related (same crop math)
  results, while different wall tiles differ from each other.
- **`world/maze/wall_overdraw_mask.gd`**: its repaint of an occluded
  wall's overdraw band must show exactly what `MazeRenderer` itself would
  currently draw there — it already computes the same `wall_tile` and
  calls the same `overdraw_rect_for(wall_tile)` `MazeRenderer` uses, so
  swapping its draw to `TileTextureVariant.draw_varied(self, _renderer.wall_texture(), _renderer.overdraw_rect_for(wall_tile), wall_tile, colors[wall_tile])`
  is guaranteed to agree with `MazeRenderer`'s own draw — both go through
  the identical shared function with the identical key, so there's no
  second implementation that could drift out of sync.
- **`world/water_tile_layer.gd`**: `_draw()` switches to
  `TileTextureVariant.draw_varied(self, texture, rect, tile, modulate_color)`
  for both the static base layer and the animated overlay layer — no
  special-casing between them for the draw call itself. Requires adding a
  `tile: Vector2i` property (currently the class has no notion of which
  tile it belongs to) and removing the now-unused `repeat: bool` property
  (see §6).
- **`world/level.gd`**: `_spawn_water_marker()` sets `base.tile = tile`
  and `overlay.tile = tile` on the two `WaterTileLayer` children it
  creates (alongside the properties it already sets), and no longer sets
  `overlay.repeat = true` (removed, see §6).

## 6. `WaterTileLayer.repeat` → `texture_repeat` (required refactor)

`draw_texture_rect_region` has no `tile`/repeat parameter — that was
specific to the old `draw_texture_rect`. Verified empirically (two
throwaway scratch scenes, deleted after use): `draw_texture_rect_region`
always stretches its `src_rect` to fill the destination exactly once,
regardless of any repeat setting; separately, the *overlay's* custom
`water_overlay.gdshader` (which manually samples
`texture(TEXTURE, UV + TIME * scroll_speed)`) continues to sample
meaningfully-varying, non-clamped content as `TIME` pushes `UV` outside
the crop's own narrow normalized window, confirmed by comparing two
captures ~2 seconds apart (different visible content in each, not a
frozen/smeared edge) — consistent with the sampler wrapping across the
full texture rather than clamping, which is what keeps the existing
scroll animation working correctly once combined with a cropped
`src_rect`. That wrap behavior is governed by the node's own
`CanvasItem.texture_repeat` property, not by anything in the draw call.

So: `WaterTileLayer.repeat` (which only ever existed to drive the old
`draw_texture_rect`'s `tile` argument) is deleted. `Level._spawn_water_marker()`
instead sets `overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED`
directly (the base layer leaves it at the CanvasItem default, i.e.
clamped — it's a static single crop, it never needs to wrap).

## 7. Testing

- `TileTextureVariant`: unit tests for determinism (same tile → same
  result across repeated calls), non-degeneracy (different tiles produce
  different crops across a sample of tile coordinates — not exhaustive,
  just enough to catch a broken/constant hash), and the defensive
  texture-smaller-than-dest clamp.
- Cross-file consistency: a test asserting `MazeRenderer`'s own wall draw
  and `WallOverdrawMask`'s repaint compute the *same* variant for the same
  wall tile — the correctness property this design actually depends on,
  not incidental coverage.
- `Level`/`WaterTileLayer`: update the existing water-marker test to
  assert `overlay.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED`
  and `base.texture_repeat == CanvasItem.TEXTURE_REPEAT_PARENT_NODE` (the
  actual default for an unset `CanvasItem.texture_repeat` — not
  `TEXTURE_REPEAT_DISABLED` as originally written here; a freshly
  constructed node's own property reads back as "inherit," not
  "disabled," verified via a live Godot probe during implementation)
  instead of the removed `repeat` field.
- Manual: boot windowed, visually confirm a run of several adjacent floor
  and wall tiles are no longer identical, and that the water overlay's
  animation still looks correct (no visible seam/pop/clamped-edge
  artifact) once its base draw also samples a per-tile crop.
