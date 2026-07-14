# Tunnel Faux-3D Walls (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make maze walls read as physically standing at floor level (a shorter, real wall front-face rising out of the floor) instead of the point-light shadow artifact that currently makes flat walls look unnaturally tall, and make sure a wall's own rendered height never hides the player from view.

**Architecture:** `MazeRenderer` (`world/maze/maze_renderer.gd`) keeps its existing custom `_draw()` approach — no real tile art or `TileSet`/`TileMapLayer` exists yet, so this plan draws taller, two-tone wall blocks (a lighter "top face" + a shorter, darker "front face") with plain `draw_rect()` calls instead of migrating to Godot's TileSet system prematurely. This is a deliberate, smaller-scope reading of `docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md`'s Phase 1: it delivers the same visual/behavioral outcome (real wall height, occlusion fade) without the added risk of hand-authoring placeholder tile atlases before real art exists. The occlusion fade is a plain per-frame alpha computation in `_draw()`, not a shader — with no real texture/TileSet in play there's no need for GPU work, and a pure GDScript function is directly unit-testable (the spec anticipated a shader; this simplifies that for the no-real-art-yet case). `Level`'s scene tree already draws `Entities` after `Renderer` (`world/level.tscn:12,21` — `Renderer` is added before `Entities`, and Godot draws 2D siblings in child order, later siblings on top), so entities already render in front of the whole wall layer with zero changes needed there. This closes the design spec's own open question about whether `Level`'s entity container needs `y_sort_enabled` — it doesn't, for this phase: since the wall layer is one flat `Node2D` drawn as a single block below all entities (not per-tile interleaved with them), there's no per-tile depth compositing to get right yet. The one case that actually matters — a wall directly hiding the player — is handled by the occlusion fade instead of Y-sorting.

**Tech Stack:** Godot 4.7, GDScript, GUT for tests.

## Global Constraints

- No change to `GridMover`, tile-stepping, collision, navigation, or any other gameplay system — this is rendering-only (per the design spec's Non-goals).
- No real 3D camera or geometry (per the design spec's Decisions).
- Pure logic gets GUT test coverage; anything about the actual pixel/visual output (does it *look* right) is verified by a real headless boot check plus manual playtest, never asserted on via a unit test alone — this project's own established pattern (see `tests/test_maze_renderer_plane.gd`, which never calls `_draw()` or inspects pixels, only state).
- Follow existing style: tabs for indentation, a doc comment on every new public function/class explaining non-obvious *why* (not what), `class_name` + typed GDScript throughout.
- Every new/changed `.gd` test file needs its `.gd.uid` sidecar committed too (run `~/.local/bin/godot --headless --path . --import` after adding a new test file, before committing — this project's own established gotcha).

---

### Task 1: Wall-occlusion pure-logic helper

**Files:**
- Modify: `world/maze/maze_renderer.gd`
- Test: `tests/test_maze_renderer_occlusion.gd` (new file)

**Interfaces:**
- Produces: `MazeRenderer.wall_occludes_position(wall_tile: Vector2i, position: Vector2, tile_size: int, overdraw: float) -> bool` (static). Task 2 calls this from `_draw_wall()`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_maze_renderer_occlusion.gd`:

```gdscript
extends GutTest
## MazeRenderer.wall_occludes_position() (tunnel faux-3D rework, Phase 1):
## a wall's rendered block pokes `overdraw` pixels above its own tile into
## the tile north of it (see maze_renderer.gd's own doc comment) -- this is
## the pure "would this wall's overdraw currently hide something standing
## at `position`" check, kept scene-tree-free so it's directly unit-
## testable. Uses tile_size=48, overdraw=16 throughout to match
## MazeRenderer's own defaults.

const TILE_SIZE := 48
const OVERDRAW := 16.0


func test_occludes_a_position_in_the_overdraw_band_directly_above_it() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,3) spans x=[96,144], y=[144,192]; its overdraw band is
	# y=[144-16, 144] = [128, 144] in the tile north of it (2,2).
	var position := Vector2(120.0, 136.0)

	assert_true(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_a_position_above_the_overdraw_band() -> void:
	var wall_tile := Vector2i(2, 3)
	# y=120 is further north than the 16px overdraw band reaches (128-144).
	var position := Vector2(120.0, 120.0)

	assert_false(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_a_position_south_of_the_wall() -> void:
	var wall_tile := Vector2i(2, 3)
	# y=160 is inside/south of the wall's own tile -- the front face only
	# ever reads as a cliff facing north, never occludes anything south.
	var position := Vector2(120.0, 160.0)

	assert_false(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_a_position_outside_its_column() -> void:
	var wall_tile := Vector2i(2, 3)
	# Same y as the first (passing) test, but x=200 is a full tile-width
	# outside wall_tile's own column (x=[96,144]).
	var position := Vector2(200.0, 136.0)

	assert_false(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_occludes_at_the_exact_tile_top_boundary() -> void:
	var wall_tile := Vector2i(2, 3)
	var position := Vector2(120.0, 144.0) # exactly the wall's own tile_top

	assert_true(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A10 "test_maze_renderer_occlusion"`
Expected: a parse/compile error (`wall_occludes_position` doesn't exist yet), or all 5 tests failing.

- [ ] **Step 3: Implement the minimal function**

In `world/maze/maze_renderer.gd`, add this static function (placement: anywhere at the class's top level, e.g. right after `_draw_grid_lines()`):

```gdscript
## True if a wall at `wall_tile` (tile coordinates) would visually overlap
## `position` (world-space) given its rendered block pokes `overdraw`
## pixels above its own tile into the tile north of it -- anything
## standing in that northern sliver would otherwise be hidden behind the
## wall's own rendered height. A pure function (no scene tree needed) so
## it's directly unit-testable -- see docs/superpowers/specs/2026-07-14-
## tunnel-visual-rework-design.md.
static func wall_occludes_position(wall_tile: Vector2i, position: Vector2, tile_size: int, overdraw: float) -> bool:
	var tile_left := float(wall_tile.x) * tile_size
	var tile_top := float(wall_tile.y) * tile_size
	if position.x < tile_left or position.x > tile_left + tile_size:
		return false
	return position.y >= tile_top - overdraw and position.y <= tile_top
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A10 "test_maze_renderer_occlusion"`
Expected: `5/5 passed.`

- [ ] **Step 5: Import + commit**

```bash
~/.local/bin/godot --headless --path . --import
git add world/maze/maze_renderer.gd tests/test_maze_renderer_occlusion.gd tests/test_maze_renderer_occlusion.gd.uid
git commit -m "MazeRenderer: wall_occludes_position() pure occlusion-fade check"
```

---

### Task 2: Taller two-tone wall rendering + occlusion fade wired into `_draw()`

**Files:**
- Modify: `world/maze/maze_renderer.gd`
- Modify: `world/level.gd` (wire the player's position into the renderer every frame)
- Test: `tests/test_maze_renderer_occlusion.gd` (add to it)

**Interfaces:**
- Consumes: `MazeRenderer.wall_occludes_position(...)` from Task 1.
- Produces: `MazeRenderer.set_fade_focus(world_position: Vector2) -> void` and `MazeRenderer.fade_focus_position: Vector2` — nothing later in this plan depends on these, but they're the seam `Level` wires up.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_maze_renderer_occlusion.gd`:

```gdscript
func _make_renderer() -> MazeRenderer:
	var renderer := MazeRenderer.new()
	add_child_autofree(renderer)
	var maze := MazeGenerator.generate(3, 3, 1)
	renderer.setup(maze, 48)
	return renderer


func test_set_fade_focus_stores_the_position() -> void:
	var renderer := _make_renderer()

	renderer.set_fade_focus(Vector2(100.0, 200.0))

	assert_eq(renderer.fade_focus_position, Vector2(100.0, 200.0))


func test_defaults_to_a_fade_focus_that_never_occludes_anything() -> void:
	var renderer := _make_renderer()

	# The default must never accidentally fade a wall before Level ever
	# calls set_fade_focus() -- Vector2.INF can't fall inside any tile's
	# finite x range, so wall_occludes_position() always returns false.
	assert_false(MazeRenderer.wall_occludes_position(Vector2i(1, 1), renderer.fade_focus_position, 48, 16.0))


func test_draw_does_not_error_with_walls_and_a_fade_focus_present() -> void:
	var renderer := _make_renderer()
	renderer.set_fade_focus(Vector2(24.0, 24.0))

	await get_tree().process_frame

	assert_true(true, "reached this point without erroring")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A10 "test_maze_renderer_occlusion"`
Expected: the first two of these three new tests fail (`set_fade_focus`/`fade_focus_position` don't exist yet); the third may error too since `_draw()` hasn't changed yet but `set_fade_focus` doesn't exist.

- [ ] **Step 3: Rewrite `_draw()` and add the fade/wall-block plumbing**

Replace the full contents of `world/maze/maze_renderer.gd` with:

```gdscript
class_name MazeRenderer
extends Node2D
## Draws a MazeData as flat floor rectangles and taller, two-tone wall
## blocks (tunnel faux-3D rework, design: docs/superpowers/specs/
## 2026-07-14-tunnel-visual-rework-design.md). A wall's rendered block is
## taller than its own 48x48 footprint -- a lighter "top face" plus a
## shorter, darker "front face" anchored to the tile's own bottom edge,
## with the extra height poking up into the tile north of it -- rather
## than a single flat-color rect, so walls read as physically standing at
## floor level instead of the old point-light shadow artifact that made
## them look unnaturally (and accidentally) tall. Placeholder colors/
## proportions, not real tile art yet -- swap for a TileMapLayer once
## SpriteCook art exists; the collision/occluder/navigation pipeline is
## built separately by Level, so it's unaffected either way.
##
## Ceiling/plane mechanics rework: open tiles render in floor_color or
## ceiling_floor_color depending on which plane the player currently
## occupies (set_active_plane(), driven by Level) — replaces the old
## per-sprite ceiling tint entirely. Wall rendering is unchanged on both
## planes for now: walls exist identically on both layers (CeilingData
## mirrors MazeData's wall geometry 1:1), and the ceiling-plane inverse
## wall treatment (front face hanging down instead of rising up) is a
## later phase, not yet built.

var _maze: MazeData
var _tile_size := 48
var floor_color := Color(0.17, 0.15, 0.13)
var ceiling_floor_color := Color(0.13, 0.17, 0.24)
var wall_top_face_color := Color(0.36, 0.31, 0.26)
var wall_front_face_color := Color(0.2, 0.16, 0.12)
## Grid lines on top of open floor tiles, so the tile-stepped movement reads
## clearly against the map.
var grid_line_color := Color(1, 1, 1, 0.08)

## How far a wall's rendered block pokes up above its own tile's top edge,
## and the height of the darker front-face band anchored to its own bottom
## edge -- see this file's own doc comment. Placeholder proportions, easy
## to retune once real tile art exists.
var wall_overdraw_height := 16.0
var wall_front_face_height := 16.0

## Any wall whose rendered block would currently overlap this world-space
## position fades to wall_fade_alpha -- set by Level every frame to the
## player's own position (occlusion fade), so a wall directly "in front of"
## the player on screen never hides them. Vector2.INF (the default) can
## never fall inside any wall's finite occlusion band, so nothing fades
## until Level calls set_fade_focus().
var fade_focus_position := Vector2.INF
var wall_fade_alpha := 0.25

var _active_plane: Level.Layer = Level.Layer.GROUND


func _ready() -> void:
	set_process(not Engine.is_editor_hint())


func _process(_delta: float) -> void:
	queue_redraw()


func setup(maze: MazeData, tile_size: int) -> void:
	_maze = maze
	_tile_size = tile_size
	queue_redraw()


## Which plane's floor color open tiles should currently draw in — the
## player's own plane (there's one camera, one local viewer).
func set_active_plane(plane: Level.Layer) -> void:
	_active_plane = plane
	queue_redraw()


## Where the occlusion fade should center -- see fade_focus_position's own
## doc comment.
func set_fade_focus(world_position: Vector2) -> void:
	fade_focus_position = world_position


func _draw() -> void:
	if _maze == null:
		return
	var open_color := floor_color if _active_plane == Level.Layer.GROUND else ceiling_floor_color
	for y in _maze.height:
		for x in _maze.width:
			if _maze.is_open(x, y):
				draw_rect(Rect2(x * _tile_size, y * _tile_size, _tile_size, _tile_size), open_color)
			else:
				_draw_wall(Vector2i(x, y))
	_draw_grid_lines()


## Draws one wall tile's block: a shorter, darker front face anchored to
## the tile's own bottom edge, with a taller, lighter top face above it
## poking up into the tile north of it. Fades both faces together if this
## wall currently occludes fade_focus_position (see wall_occludes_position).
func _draw_wall(tile: Vector2i) -> void:
	var alpha := wall_fade_alpha if wall_occludes_position(tile, fade_focus_position, _tile_size, wall_overdraw_height) else 1.0
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var block_top := tile_top - wall_overdraw_height
	var front_face_top := tile_bottom - wall_front_face_height
	draw_rect(Rect2(tile_left, block_top, _tile_size, front_face_top - block_top),
		Color(wall_top_face_color, wall_top_face_color.a * alpha))
	draw_rect(Rect2(tile_left, front_face_top, _tile_size, wall_front_face_height),
		Color(wall_front_face_color, wall_front_face_color.a * alpha))


## True if a wall at `wall_tile` (tile coordinates) would visually overlap
## `position` (world-space) given its rendered block pokes `overdraw`
## pixels above its own tile into the tile north of it -- anything
## standing in that northern sliver would otherwise be hidden behind the
## wall's own rendered height. A pure function (no scene tree needed) so
## it's directly unit-testable -- see docs/superpowers/specs/2026-07-14-
## tunnel-visual-rework-design.md.
static func wall_occludes_position(wall_tile: Vector2i, position: Vector2, tile_size: int, overdraw: float) -> bool:
	var tile_left := float(wall_tile.x) * tile_size
	var tile_top := float(wall_tile.y) * tile_size
	if position.x < tile_left or position.x > tile_left + tile_size:
		return false
	return position.y >= tile_top - overdraw and position.y <= tile_top


func _draw_grid_lines() -> void:
	var width_px := _maze.width * _tile_size
	var height_px := _maze.height * _tile_size
	for x in (_maze.width + 1):
		var px := x * _tile_size
		draw_line(Vector2(px, 0), Vector2(px, height_px), grid_line_color)
	for y in (_maze.height + 1):
		var py := y * _tile_size
		draw_line(Vector2(0, py), Vector2(width_px, py), grid_line_color)
```

- [ ] **Step 4: Wire the player's position into the renderer every frame**

In `world/level.gd`, find `_process(delta: float)` (currently handles larva spawning and Sense outlines) and add the fade-focus wiring at its top:

```gdscript
func _process(delta: float) -> void:
	if maze == null:
		return
	if player != null and is_instance_valid(player):
		_renderer.set_fade_focus(player.global_position)
	_spawn_accum += delta
	if _spawn_accum >= LARVA_SPAWN_INTERVAL:
		_spawn_accum = 0.0
		if get_tree().get_nodes_in_group("larvae").size() < _larva_cap:
			_spawn_larva_at_random()
	if _sense_active:
		_update_sense_outlines()
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A10 "test_maze_renderer_occlusion"`
Expected: `8/8 passed.`

- [ ] **Step 6: Run the full suite to check for regressions**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | tail -20`
Expected: same pass count as before this task plus the 3 new tests, no new failures. (One pre-existing, unrelated flaky test — `test_open_ground_does_not_block_a_spawned_larva` in `tests/test_larva_hazards.gd` — may intermittently fail; that's a known, already-present flake unrelated to this change, not something to chase here.)

- [ ] **Step 7: Headless boot check**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"`
Expected: no output (clean boot).

- [ ] **Step 8: Import + commit**

```bash
~/.local/bin/godot --headless --path . --import
git add world/maze/maze_renderer.gd world/level.gd tests/test_maze_renderer_occlusion.gd
git commit -m "MazeRenderer: taller two-tone wall blocks + player occlusion fade"
```

---

### Task 3: Soften the player's vision-light shadows

**Files:**
- Modify: `entities/player/player.tscn`

**Interfaces:**
- Consumes: nothing from Tasks 1/2.
- Produces: nothing later in this plan depends on this.

- [ ] **Step 1: Edit the VisionLight node**

In `entities/player/player.tscn`, find the `VisionLight` node:

```
[node name="VisionLight" type="PointLight2D" parent="."]
texture = SubResource("GradientTexture2D_light")
energy = 1.5
shadow_enabled = true
texture_scale = 1.3
```

Replace it with:

```
[node name="VisionLight" type="PointLight2D" parent="."]
texture = SubResource("GradientTexture2D_light")
energy = 1.5
shadow_enabled = true
shadow_color = Color(0, 0, 0, 0.55)
shadow_filter = 1
shadow_filter_smooth = 3.0
texture_scale = 1.3
```

This keeps shadows (some shadow is part of what makes the new wall height read as real, per the design spec), but at partial opacity (`0.55` alpha instead of the engine default fully-opaque black) with a soft PCF5 filter (`shadow_filter = 1`) and blur (`shadow_filter_smooth = 3.0`), instead of the harsh, fully-opaque hard-edged shadow that used to make flat walls read as unnaturally tall.

- [ ] **Step 2: Run the full test suite**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | tail -15`
Expected: no change in pass count (`.tscn` property values aren't exercised by any GUT test — this is a visual-only tweak).

- [ ] **Step 3: Headless boot check**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"`
Expected: no output (clean boot).

- [ ] **Step 4: Manual playtest verification**

This is a visual-only change with no automated test — actually launch the game (`~/.local/bin/godot --path . res://world/world.tscn`) and confirm: shadows off wall edges read as a soft dimming rather than a stark black wedge, and walls no longer read as "standing rubble" the way they did before this plan's Task 2 + this task combined. This step doesn't get a checkbox for "expected output" the way the others do — it's a subjective look-and-feel call for a human to make.

- [ ] **Step 5: Commit**

```bash
git add entities/player/player.tscn
git commit -m "Player: soften VisionLight shadow now that wall height is intentional"
```
