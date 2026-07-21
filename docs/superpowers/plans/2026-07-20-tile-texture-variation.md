# Per-Tile Texture Variation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop every floor/wall/water tile from showing the pixel-identical crop of its source texture by replacing `draw_texture_rect(..., tile=true, ...)` with a per-tile-coordinate hashed crop, everywhere it's used.

**Architecture:** One new pure-function module, `TileTextureVariant` (`world/maze/tile_texture_variant.gd`), computes a deterministic `(src_rect, flip_h, flip_v)` from a tile's own `Vector2i` plus the destination size and source texture size, and a thin `draw_varied()` wrapper issues the actual `draw_texture_rect_region(...)` call. Every existing per-tile draw site (`FloorRenderer`, `MazeRenderer`'s three wall-face draws, `WallOverdrawMask`'s repaint, `WaterTileLayer`'s base and overlay) switches to this one shared function, keyed by the tile it's drawing. `WallOverdrawMask` needing to exactly match `MazeRenderer`'s own rendering for a given wall tile falls out for free: both call the identical function with the identical arguments, so there's no second implementation that could drift.

**Tech Stack:** Godot 4.7 (GDScript), GUT test framework.

## Global Constraints

- Godot binary: `~/.local/bin/godot`. All headless commands run from the repo root (`/home/e3h1x/workspace/burrow/.claude/worktrees/art-pipeline-design`).
- New `.gd` files leave a `.gd.uid` sidecar that must be committed alongside the file.
- **GDScript's `%` keeps the sign of the dividend for negative operands**, and `hash()` can return a negative `int`. Always `absi(hash(tile))` before any modulo, or a tile can get a negative crop offset — a real, easy-to-miss bug, not a style preference.
- This project's established test convention for renderer `_draw()` methods is **no pixel assertions** (see `test_floor_renderer.gd`'s own doc comment: "No pixel assertions -- this project's own established pattern -- just that setup() doesn't error"). Pure logic (like `TileTextureVariant.variant_for()`, or existing examples `MazeRenderer.wall_occludes_extent()`/`overdraw_alpha_for_offset()`) gets direct unit tests; renderer call sites that just wire a pure function in get "doesn't error" coverage via the existing test suite, not new pixel-inspecting tests. Follow this convention — don't invent pixel/rendering assertions for Tasks 2-5 below.
- `draw_texture_rect_region(texture, rect, src_rect, modulate)` always stretches `src_rect` to fill `rect` exactly once — it has no `tile`/repeat behavior of its own (verified empirically during design). ~~Flipping is achieved by giving `rect` a negative width/height (the standard Godot idiom), never by modifying `src_rect`.~~ **SUPERSEDED by commit `d00c4ec`:** Task 6's manual visual validation found this project's actual runtime (GL Compatibility / Mesa d3d12 on WSL2) silently ignores the sign of a negative-size `rect`, drawing `abs(size)` pixels forward instead of mirroring — shifting flipped tiles onto a neighboring cell and leaving gaps that read as solid black. The shipped `TileTextureVariant.draw_varied()` flips via `CanvasItem.draw_set_transform()` (scale `-1` on the flipped axis) instead, never constructing a negative-size `Rect2` at all — see that function's own doc comment for the full mechanism and evidence.
- GUT suite command: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`. Known pre-existing flakiness: this suite has order/timing-dependent failures unrelated to any of this work (different runs fail different timing-sensitive tests, reproduced on an unmodified `main` too during the prior water-tile-overlay plan's review) — don't chase a failure here unless it's in a file this plan actually touches.

---

### Task 1: `TileTextureVariant` — the shared pure-function module

**Files:**
- Create: `world/maze/tile_texture_variant.gd`
- Test: `tests/test_tile_texture_variant.gd`

**Interfaces:**
- Produces: `class_name TileTextureVariant` with
  `static func variant_for(tile: Vector2i, dest_size: Vector2, texture_size: Vector2) -> Dictionary`
  (keys `"src_rect": Rect2`, `"flip_h": bool`, `"flip_v": bool`) and
  `static func draw_varied(canvas_item: CanvasItem, texture: Texture2D, dest_rect: Rect2, tile: Vector2i, modulate: Color = Color.WHITE) -> void`.
  Every later task calls `draw_varied()` from inside some `CanvasItem`'s own `_draw()`, passing `self` as `canvas_item`.

- [ ] **Step 1: Write the failing tests**

Write `tests/test_tile_texture_variant.gd`:

```gdscript
extends GutTest
## TileTextureVariant: deterministic per-tile crop + flip so adjacent
## tiles drawn from the same small source texture don't show pixel-
## identical content (root cause: draw_texture_rect(tile=true) always
## resets UV to a draw call's own rect origin -- see
## docs/superpowers/specs/2026-07-20-tile-texture-variation-design.md).
## Pure-function tests only, per this project's own established pattern
## for renderer logic (see MazeRenderer.wall_occludes_extent() etc.) --
## no scene tree needed.


func test_variant_for_is_deterministic_for_the_same_tile() -> void:
	var a := TileTextureVariant.variant_for(Vector2i(3, 4), Vector2(48, 48), Vector2(200, 200))
	var b := TileTextureVariant.variant_for(Vector2i(3, 4), Vector2(48, 48), Vector2(200, 200))

	assert_eq(a.src_rect, b.src_rect)
	assert_eq(a.flip_h, b.flip_h)
	assert_eq(a.flip_v, b.flip_v)


func test_variant_for_differs_across_a_sample_of_tiles() -> void:
	var seen_offsets := {}
	for x in range(6):
		for y in range(6):
			var v := TileTextureVariant.variant_for(Vector2i(x, y), Vector2(48, 48), Vector2(200, 200))
			seen_offsets[v.src_rect.position] = true

	assert_gt(seen_offsets.size(), 1, "a 6x6 sample of tiles should not all pick the identical crop offset")


func test_variant_for_never_exceeds_texture_bounds() -> void:
	for x in range(10):
		for y in range(10):
			var v: Dictionary = TileTextureVariant.variant_for(Vector2i(x, y), Vector2(48, 16), Vector2(80, 71))
			assert_true(v.src_rect.position.x >= 0 and v.src_rect.position.y >= 0,
				"crop offset must never be negative (GDScript's %% keeps the dividend's sign on negative hashes)")
			assert_true(v.src_rect.position.x + v.src_rect.size.x <= 80,
				"crop must never sample past the texture's own width")
			assert_true(v.src_rect.position.y + v.src_rect.size.y <= 71,
				"crop must never sample past the texture's own height")


func test_variant_for_clamps_to_zero_offset_when_texture_is_smaller_than_dest() -> void:
	var v := TileTextureVariant.variant_for(Vector2i(7, 7), Vector2(48, 48), Vector2(20, 20))

	assert_eq(v.src_rect.position, Vector2(0, 0))
	assert_eq(v.src_rect.size, Vector2(48, 48))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_tile_texture_variant.gd -gexit
```

Expected: FAIL — `TileTextureVariant` is an unknown identifier (the class doesn't exist yet).

- [ ] **Step 3: Implement `TileTextureVariant`**

Write `world/maze/tile_texture_variant.gd`:

```gdscript
class_name TileTextureVariant
extends RefCounted
## Deterministic per-tile crop + flip so adjacent tiles drawn from the
## same small source texture don't show pixel-identical content (root
## cause: draw_texture_rect(tile=true) always resets UV sampling to a
## draw call's own rect origin, not to the rect's position in world
## space -- every FloorRenderer/MazeRenderer/WallOverdrawMask/
## WaterTileLayer tile ended up showing the source texture's identical
## top-left corner. See docs/superpowers/specs/2026-07-20-tile-texture-
## variation-design.md for the full writeup, including how this was
## verified). Keyed purely by tile coordinate -- no time/frame
## dependence, so a given tile always renders the same way and
## queue_redraw() never causes visible jitter, and so two independent
## draw sites for the SAME tile (MazeRenderer's own wall draw and
## WallOverdrawMask's occluded-overdraw repaint) are guaranteed to agree
## without duplicating this logic -- both just call draw_varied() with
## the same tile and get the identical result.


## Pure: given a tile, the size of the rect it'll be drawn into, and the
## source texture's own size, returns the crop (in texture pixels) and
## flip flags to use. Split out from draw_varied() so it's directly
## unit-testable without a scene tree, matching this codebase's
## established pattern for renderer logic (MazeRenderer.wall_occludes_
## extent(), overdraw_alpha_for_offset(), etc.).
static func variant_for(tile: Vector2i, dest_size: Vector2, texture_size: Vector2) -> Dictionary:
	# absi() matters here: GDScript's %% keeps the dividend's sign, so a
	# negative hash() would otherwise produce a negative offset.
	var h := absi(hash(tile))
	var max_x := maxi(0, int(texture_size.x) - int(dest_size.x))
	var max_y := maxi(0, int(texture_size.y) - int(dest_size.y))
	var offset_x := 0 if max_x == 0 else (h % (max_x + 1))
	# Divide by a distinct prime before the y modulo so x/y offsets, and
	# the flip bits below, aren't visibly correlated with each other.
	var offset_y := 0 if max_y == 0 else ((h / 4099) % (max_y + 1))
	var flip_h := bool((h / 65537) & 1)
	var flip_v := bool((h / 131111) & 1)
	return {
		"src_rect": Rect2(offset_x, offset_y, dest_size.x, dest_size.y),
		"flip_h": flip_h,
		"flip_v": flip_v,
	}


## Draws `texture` into `dest_rect` on `canvas_item`, using variant_for()'s
## per-tile crop and flip -- must be called from inside canvas_item's own
## _draw() (Godot's draw_* methods only work mid-draw-pass). Replaces
## draw_texture_rect(texture, dest_rect, tile=true, modulate) at every
## call site that used to rely on that flag; draw_texture_rect_region has
## no repeat/tile behavior of its own; regardless, it always stretches
## src_rect to fill dest_rect exactly once (verified during design).
## Flipping is done via a negative-size dest rect (the standard Godot
## idiom), not by touching src_rect.
static func draw_varied(canvas_item: CanvasItem, texture: Texture2D, dest_rect: Rect2, tile: Vector2i, modulate: Color = Color.WHITE) -> void:
	var variant := variant_for(tile, dest_rect.size, texture.get_size())
	var flipped := Rect2(
		dest_rect.position.x + (dest_rect.size.x if variant.flip_h else 0.0),
		dest_rect.position.y + (dest_rect.size.y if variant.flip_v else 0.0),
		-dest_rect.size.x if variant.flip_h else dest_rect.size.x,
		-dest_rect.size.y if variant.flip_v else dest_rect.size.y
	)
	canvas_item.draw_texture_rect_region(texture, flipped, variant.src_rect, modulate)
```

**SUPERSEDED by commit `d00c4ec` — do not copy the code block above.** This negative-size-dest-rect flip renders broken on this project's actual runtime (see the Global Constraints note above for the full story: Task 6's manual visual check found it silently ignored the rect's sign, shifting flipped tiles onto a neighboring cell and leaving gaps that read as solid black across roughly half the map). The shipped `draw_varied()` uses `CanvasItem.draw_set_transform()` instead — read `world/maze/tile_texture_variant.gd` directly for the actual, correct implementation and its doc comment.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_tile_texture_variant.gd -gexit
```

Expected: PASS, all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add world/maze/tile_texture_variant.gd world/maze/tile_texture_variant.gd.uid tests/test_tile_texture_variant.gd tests/test_tile_texture_variant.gd.uid
git commit -m "Add TileTextureVariant: deterministic per-tile texture crop + flip"
```

---

### Task 2: Wire into `FloorRenderer`

**Files:**
- Modify: `world/maze/floor_renderer.gd:45`

**Interfaces:**
- Consumes: `TileTextureVariant.draw_varied()` (Task 1).

- [ ] **Step 1: Confirm the existing test still passes before changing anything**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_floor_renderer.gd -gexit
```

Expected: PASS (baseline, before this task's change).

- [ ] **Step 2: Replace the draw call**

In `world/maze/floor_renderer.gd`, replace line 45:

```gdscript
				draw_texture_rect(_floor_texture, Rect2(x * _tile_size, y * _tile_size, _tile_size, _tile_size), true, tint)
```

with:

```gdscript
				TileTextureVariant.draw_varied(self, _floor_texture, Rect2(x * _tile_size, y * _tile_size, _tile_size, _tile_size), Vector2i(x, y), tint)
```

- [ ] **Step 3: Run the test again to confirm no regression**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_floor_renderer.gd -gexit
```

Expected: PASS — same result as Step 1 (this project's tests for renderer `_draw()` methods only check "doesn't error", per the Global Constraints note; the visual improvement itself is confirmed manually in Task 6).

- [ ] **Step 4: Commit**

```bash
git add world/maze/floor_renderer.gd
git commit -m "FloorRenderer: use TileTextureVariant instead of tile=true repeat"
```

---

### Task 3: Wire into `MazeRenderer`

**Files:**
- Modify: `world/maze/maze_renderer.gd:332-342` (`_draw_wall_ground`), `world/maze/maze_renderer.gd:354-364` (`_draw_wall_ceiling`)

**Interfaces:**
- Consumes: `TileTextureVariant.draw_varied()` (Task 1).
- Produces: no change to `MazeRenderer`'s public interface (`wall_texture()`, `tinted_wall_top_face_color()`, `overdraw_rect_for()` all unchanged) — `WallOverdrawMask` (Task 4) still calls those exactly as before.

- [ ] **Step 1: Confirm existing tests still pass before changing anything**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_maze_renderer_occlusion.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_maze_renderer_plane.gd -gexit
```

Expected: PASS on both (baseline).

- [ ] **Step 2: Replace the draw calls in `_draw_wall_ground`**

In `world/maze/maze_renderer.gd`, replace the current `_draw_wall_ground` body (lines 332-342):

```gdscript
func _draw_wall_ground(tile: Vector2i) -> void:
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var front_face_top := tile_bottom - wall_front_face_height
	var overdraw_rect := overdraw_rect_for(tile)
	var own_top_face := Rect2(tile_left, tile_top, _tile_size, front_face_top - tile_top)
	var top_tint := _tinted(wall_top_face_color)
	draw_texture_rect(_wall_texture, overdraw_rect, true, Color(top_tint, top_tint.a * overdraw_alpha_for(tile)))
	draw_texture_rect(_wall_texture, own_top_face, true, top_tint)
	draw_texture_rect(_wall_texture, Rect2(tile_left, front_face_top, _tile_size, wall_front_face_height), true, _tinted(wall_front_face_color))
```

with:

```gdscript
func _draw_wall_ground(tile: Vector2i) -> void:
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var front_face_top := tile_bottom - wall_front_face_height
	var overdraw_rect := overdraw_rect_for(tile)
	var own_top_face := Rect2(tile_left, tile_top, _tile_size, front_face_top - tile_top)
	var top_tint := _tinted(wall_top_face_color)
	TileTextureVariant.draw_varied(self, _wall_texture, overdraw_rect, tile, Color(top_tint, top_tint.a * overdraw_alpha_for(tile)))
	TileTextureVariant.draw_varied(self, _wall_texture, own_top_face, tile, top_tint)
	TileTextureVariant.draw_varied(self, _wall_texture, Rect2(tile_left, front_face_top, _tile_size, wall_front_face_height), tile, _tinted(wall_front_face_color))
```

- [ ] **Step 3: Replace the draw calls in `_draw_wall_ceiling`**

Replace the current `_draw_wall_ceiling` body (lines 354-364):

```gdscript
func _draw_wall_ceiling(tile: Vector2i) -> void:
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var front_face_bottom := tile_top + wall_front_face_height
	var overdraw_rect := overdraw_rect_for(tile)
	var own_top_face := Rect2(tile_left, front_face_bottom, _tile_size, tile_bottom - front_face_bottom)
	var top_tint := _tinted(wall_top_face_color)
	draw_texture_rect(_wall_texture, own_top_face, true, _tinted(_own_body_color_for(tile)))
	draw_texture_rect(_wall_texture, overdraw_rect, true, Color(top_tint, top_tint.a * overdraw_alpha_for(tile)))
	draw_texture_rect(_wall_texture, Rect2(tile_left, tile_top, _tile_size, wall_front_face_height), true, _tinted(wall_front_face_color))
```

with:

```gdscript
func _draw_wall_ceiling(tile: Vector2i) -> void:
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var front_face_bottom := tile_top + wall_front_face_height
	var overdraw_rect := overdraw_rect_for(tile)
	var own_top_face := Rect2(tile_left, front_face_bottom, _tile_size, tile_bottom - front_face_bottom)
	var top_tint := _tinted(wall_top_face_color)
	TileTextureVariant.draw_varied(self, _wall_texture, own_top_face, tile, _tinted(_own_body_color_for(tile)))
	TileTextureVariant.draw_varied(self, _wall_texture, overdraw_rect, tile, Color(top_tint, top_tint.a * overdraw_alpha_for(tile)))
	TileTextureVariant.draw_varied(self, _wall_texture, Rect2(tile_left, tile_top, _tile_size, wall_front_face_height), tile, _tinted(wall_front_face_color))
```

- [ ] **Step 4: Run the tests again to confirm no regression**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_maze_renderer_occlusion.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_maze_renderer_plane.gd -gexit
```

Expected: PASS on both, same as Step 1.

- [ ] **Step 5: Commit**

```bash
git add world/maze/maze_renderer.gd
git commit -m "MazeRenderer: use TileTextureVariant instead of tile=true repeat"
```

---

### Task 4: Wire into `WallOverdrawMask`

**Files:**
- Modify: `world/maze/wall_overdraw_mask.gd:77`

**Interfaces:**
- Consumes: `TileTextureVariant.draw_varied()` (Task 1). Relies on `MazeRenderer` (Task 3) already using the same function for the same `wall_tile`/`overdraw_rect_for(wall_tile)`/`wall_texture()` inputs — that's what makes the two repaints agree; no new coordination code is needed here.

- [ ] **Step 1: Confirm the existing tests still pass before changing anything**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_wall_overdraw_mask.gd -gexit
```

Expected: PASS (baseline — this file has ~20 tests, none of which inspect pixels; they check color/alpha *values* returned by `_paint_color_for()`/`_occluded_wall_tile_colors()`, which this task doesn't touch).

- [ ] **Step 2: Replace the draw call**

In `world/maze/wall_overdraw_mask.gd`, replace line 77:

```gdscript
		draw_texture_rect(_renderer.wall_texture(), _renderer.overdraw_rect_for(wall_tile), true, colors[wall_tile])
```

with:

```gdscript
		TileTextureVariant.draw_varied(self, _renderer.wall_texture(), _renderer.overdraw_rect_for(wall_tile), wall_tile, colors[wall_tile])
```

- [ ] **Step 3: Run the tests again to confirm no regression**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_wall_overdraw_mask.gd -gexit
```

Expected: PASS — same result as Step 1.

- [ ] **Step 4: Commit**

```bash
git add world/maze/wall_overdraw_mask.gd
git commit -m "WallOverdrawMask: use TileTextureVariant, matching MazeRenderer's own wall draw"
```

---

### Task 5: Wire into `WaterTileLayer` and `Level`, retire `repeat`

**Files:**
- Modify: `world/water_tile_layer.gd` (whole file)
- Modify: `world/level.gd:664-683` (`_spawn_water_marker`)
- Test: `tests/test_level_hazard_helpers.gd:80-96`

**Interfaces:**
- Consumes: `TileTextureVariant.draw_varied()` (Task 1).
- Produces: `WaterTileLayer` gains a `tile: Vector2i` property; loses its `repeat: bool` property (superseded by `CanvasItem.texture_repeat`, which `Level._spawn_water_marker()` now sets directly on the overlay child). `Level._spawn_water_marker(tile: Vector2i) -> Node2D`'s own signature and `_water_nodes` bookkeeping are unchanged.

- [ ] **Step 1: Update the failing test first**

In `tests/test_level_hazard_helpers.gd`, replace the last three lines of `test_set_water_at_spawns_a_distinct_water_marker_not_the_pit_marker` (currently lines 93-96):

```gdscript
	var overlay: WaterTileLayer = marker.get_child(1)
	assert_eq(overlay.texture, preload("res://assets/textures/water_overlay_material.png"))
	assert_eq(overlay.material, level._ground_layer.water_overlay_material())
	assert_true(overlay.repeat, "overlay must repeat so its scrolled UV wraps instead of clamping at the texture edge")
```

with:

```gdscript
	var overlay: WaterTileLayer = marker.get_child(1)
	assert_eq(overlay.texture, preload("res://assets/textures/water_overlay_material.png"))
	assert_eq(overlay.material, level._ground_layer.water_overlay_material())
	assert_eq(overlay.texture_repeat, CanvasItem.TEXTURE_REPEAT_ENABLED,
		"overlay must wrap so its scrolled UV doesn't clamp at the texture edge")
	assert_eq(base.texture_repeat, CanvasItem.TEXTURE_REPEAT_DISABLED,
		"base is a static single crop -- it never needs to wrap")
```

**SUPERSEDED:** this plan text is factually wrong about Godot's actual default. Task 5's implementer found (and the task reviewer independently confirmed via a live probe) that a freshly-constructed `CanvasItem`'s own `texture_repeat` defaults to `TEXTURE_REPEAT_PARENT_NODE` (0), not `TEXTURE_REPEAT_DISABLED` (1) — the getter returns the node's own unset state, not a resolved/inherited value. The shipped test correctly asserts `CanvasItem.TEXTURE_REPEAT_PARENT_NODE` instead; see `tests/test_level_hazard_helpers.gd`'s actual assertion, not the snippet above.

- [ ] **Step 2: Run the test to verify it fails**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_level_hazard_helpers.gd -gexit
```

Expected: FAIL — `overlay.repeat` no longer exists to assert on being removed is the intent, but at this point in the sequence the code hasn't changed yet, so this will actually fail because `overlay.texture_repeat` is still `TEXTURE_REPEAT_DISABLED` (the code hasn't been updated to enable it) — either way, this is the expected red state before Step 3's implementation.

- [ ] **Step 3: Update `WaterTileLayer`**

Replace the entire contents of `world/water_tile_layer.gd`:

```gdscript
class_name WaterTileLayer
extends Node2D
## A single textured square, drawn to exactly fill one maze tile -- used as
## a child layer of Level's water-tile marker (see
## Level._spawn_water_marker()). Two of these stack per flooded tile: a
## static wet-floor base (GroundLayer.dim_material()) and an animated
## water overlay on top (GroundLayer.water_overlay_material()). Both use
## TileTextureVariant.draw_varied() (docs/superpowers/specs/2026-07-20-
## tile-texture-variation-design.md) so a flooded tile doesn't show the
## identical crop every other flooded tile does -- the same fix applied
## to FloorRenderer/MazeRenderer/WallOverdrawMask. Whether this layer
## should wrap (needed for the overlay's TIME-scrolled shader UV to not
## clamp at the texture edge) is set directly on the CanvasItem's own
## texture_repeat property by Level._spawn_water_marker(), not by a field
## on this class -- draw_texture_rect_region (unlike the old
## draw_texture_rect(tile=true) this replaced) has no repeat argument of
## its own.

var texture: Texture2D
var tile_size: float
var modulate_color := Color(1, 1, 1, 1)
var tile: Vector2i


func _draw() -> void:
	var half := tile_size * 0.5
	var rect := Rect2(-half, -half, tile_size, tile_size)
	TileTextureVariant.draw_varied(self, texture, rect, tile, modulate_color)
```

- [ ] **Step 4: Update `Level._spawn_water_marker()`**

In `world/level.gd`, replace the current function body (lines 664-683):

```gdscript
func _spawn_water_marker(tile: Vector2i) -> Node2D:
	var container := Node2D.new()
	container.position = _tile_centre(tile.x, tile.y)
	_ground_layer.add_child(container)

	var base := WaterTileLayer.new()
	base.texture = _wet_floor_texture
	base.tile_size = TILE_SIZE
	container.add_child(base)
	base.material = _ground_layer.dim_material()

	var overlay := WaterTileLayer.new()
	overlay.texture = _water_overlay_texture
	overlay.tile_size = TILE_SIZE
	overlay.repeat = true
	overlay.modulate_color = Color(1, 1, 1, WATER_OVERLAY_ALPHA)
	container.add_child(overlay)
	overlay.material = _ground_layer.water_overlay_material()

	return container
```

with:

```gdscript
func _spawn_water_marker(tile: Vector2i) -> Node2D:
	var container := Node2D.new()
	container.position = _tile_centre(tile.x, tile.y)
	_ground_layer.add_child(container)

	var base := WaterTileLayer.new()
	base.texture = _wet_floor_texture
	base.tile_size = TILE_SIZE
	base.tile = tile
	container.add_child(base)
	base.material = _ground_layer.dim_material()

	var overlay := WaterTileLayer.new()
	overlay.texture = _water_overlay_texture
	overlay.tile_size = TILE_SIZE
	overlay.tile = tile
	overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	overlay.modulate_color = Color(1, 1, 1, WATER_OVERLAY_ALPHA)
	container.add_child(overlay)
	overlay.material = _ground_layer.water_overlay_material()

	return container
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_level_hazard_helpers.gd -gexit
```

Expected: PASS, all tests in `tests/test_level_hazard_helpers.gd`.

- [ ] **Step 6: Commit**

```bash
git add world/water_tile_layer.gd world/level.gd tests/test_level_hazard_helpers.gd
git commit -m "WaterTileLayer: use TileTextureVariant, retire repeat for texture_repeat"
```

---

### Task 6: Full validation and visual confirmation

**Files:** none created or modified — this task only runs checks.

**Interfaces:**
- Consumes: everything from Tasks 1-5.

- [ ] **Step 1: Full GUT suite**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
```

Expected: no new failures beyond the pre-existing, order-dependent flakiness already documented (Global Constraints). If a failure is in `test_tile_texture_variant.gd`, `test_floor_renderer.gd`, `test_maze_renderer_occlusion.gd`, `test_maze_renderer_plane.gd`, `test_wall_overdraw_mask.gd`, or `test_level_hazard_helpers.gd`, that's this plan's own regression — stop and fix before continuing.

- [ ] **Step 2: Import + boot smoke test**

```bash
~/.local/bin/godot --headless --path . --import
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"
```

Expected: no new errors/warnings.

- [ ] **Step 3: Manual visual check**

Boot the game windowed (`~/.local/bin/godot --path . res://world/world.tscn`) and confirm:
- A run of several adjacent floor tiles are visibly distinct from each other, not an obvious identical repeat.
- A run of several adjacent wall tiles (both top face and front face) are visibly distinct from each other.
- Trigger a flood (`WaterIngress` naturally, or `level.set_water_at(tile, true)` via a temporary script) and confirm: the wet-floor base and animated overlay both still render correctly, the overlay's animation still visibly drifts over a couple of seconds the same way it did before this change, and there's no visible streaking, clamped-edge smear, or sudden pop/seam as it animates (the failure mode this task's shader-wrap verification was specifically checking against).

If using any temporary script/scene/autoload for this check, remove it afterward — confirm with `git status --short` that nothing scratch remains.

- [ ] **Step 4: Final `git status` check**

```bash
git status --short
```

Expected: clean.
