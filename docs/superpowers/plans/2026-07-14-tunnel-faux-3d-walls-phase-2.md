# Tunnel Faux-3D Walls (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the ceiling plane its own inverse wall treatment (front faces hang down instead of rising up), make the ground floor read as a hazy, out-of-focus background layer while the player is on the ceiling instead of the current flat floor-color swap, and switch the Enemy's existing off-plane dimming from a flat alpha fade to the same hazy/desaturated look.

**Architecture:** `MazeRenderer` (`world/maze/maze_renderer.gd`) gets a per-plane wall-drawing variant — `_draw_wall_ground()`/`_draw_wall_ceiling()` — driven by its existing `_active_plane`, with a mirrored `wall_occludes_position_ceiling()` fade check alongside Phase 1's ground-plane one. Floor rendering moves out of `MazeRenderer` entirely into a new `FloorRenderer` node living inside a new `GroundLayer` (`CanvasGroup`), which carries a small new hand-written shader (`assets/shaders/ground_dim.gdshader`, this project's second shader after `outline.gdshader`) doing a cheap desaturate+darken pass — no blur, no `SubViewport`, matching the design doc's own recommendation to start simple. This retires `MazeRenderer.ceiling_floor_color` (shipped in sub-project F): a real background layer that dims independently makes the old floor-recolor trick for "which plane am I on" redundant. `GroundLayer` also absorbs always-ground entities that today get parented under `Entities`/`Level` directly — larvae, `WorldItemPickup`, and hazard markers — confirmed via grep that none carry a `PlaneComponent`, so this only changes where they're parented for rendering, not any plane-aware behavior. Both Centipede types (the obstacle `Centipede` and `CentipedeExpressRider`) are deliberately excluded from `GroundLayer`: a Centipede's body is the same width as the tunnel itself, so it must read identically regardless of which plane the player is viewing from, unlike a loose larva or item — both stay parented under `Entities`, undimmed. `Player`/`Enemy` also stay under the existing `Entities` node — but (correction, 2026-07-14, after Task 3) Enemy's existing per-entity off-plane dimming switches from a flat `body_alpha` fade to the same desaturate+darken formula `GroundLayer` uses, for visual consistency across the whole "off-plane/background" language. Since `Player`/`Enemy` sprites already share one `ShaderMaterial` (`outline.gdshader`, via `OutlineFx`) for their outline/Camouflage effects, and a `CanvasItem` can only ever hold one `material`, the desaturate formula is merged directly into `outline.gdshader` as new uniforms rather than duplicated into a second material — `GroundLayer`'s dedicated `ground_dim.gdshader` stays separate since a `CanvasGroup` has no outline/Camouflage concerns to share a material with. Full design: `docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md`'s Phase 2 section (revised 2026-07-14 after Phase 1 shipped, then corrected twice more the same day: once on Centipede scope, once on Enemy's dim treatment).

**Tech Stack:** Godot 4.7, GDScript, GUT for tests.

## Global Constraints

- No change to `GridMover`, tile-stepping, collision, navigation, or any other gameplay system — this is rendering-only (per the design spec's Non-goals).
- No real 3D camera or geometry (per the design spec's Decisions).
- No `TileMapLayer`/`TileSet` migration this phase either — `assets/tilesets/` is still empty, so this stays hand-drawn `_draw()`/`Polygon2D` content, same as Phase 1 actually shipped.
- No underside/belly sprite this phase — no art exists yet (confirmed via `spritecook-assets.json`); deferred to a future pass.
- Pure logic gets GUT test coverage; anything about the actual pixel/visual output (does it *look* right) is verified by a real headless boot check plus manual playtest, never asserted on via a unit test alone — this project's own established pattern.
- Follow existing style: tabs for indentation, a doc comment on every new public function/class explaining non-obvious *why* (not what), `class_name` + typed GDScript throughout.
- Every new/changed `.gd` test file needs its `.gd.uid` sidecar committed too (run `~/.local/bin/godot --headless --path . --import` after adding a new test file, before committing).
- Never call a `Node2D`'s `_draw()` override directly in a test — `draw_rect()`/`draw_line()` require an active engine redraw pass. Use `await get_tree().process_frame` (or just call the public setup method and trust the engine's own redraw cycle) instead, matching this project's own established pattern (`tests/test_maze_renderer_plane.gd`, `tests/test_maze_renderer_occlusion.gd`).

---

### Task 1: Ceiling-plane wall mirroring in `MazeRenderer`

**Files:**
- Modify: `world/maze/maze_renderer.gd`
- Test: `tests/test_maze_renderer_occlusion.gd` (add to it)

**Interfaces:**
- Produces: `MazeRenderer.wall_occludes_position_ceiling(wall_tile: Vector2i, position: Vector2, tile_size: int, overdraw: float) -> bool` (static). Nothing later in this plan depends on this directly — it's wired into `_draw_wall_ceiling()` in this same task.
- Consumes: nothing from later tasks.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_maze_renderer_occlusion.gd` (after the existing `test_occludes_at_the_exact_tile_top_boundary` function, before the `_make_renderer()` helper):

```gdscript
func test_occludes_ceiling_a_position_in_the_overdraw_band_directly_below_it() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,3) spans x=[96,144], y=[144,192]; its ceiling overdraw band is
	# y=[192, 192+16] = [192, 208] in the tile south of it (2,4).
	var position := Vector2(120.0, 200.0)

	assert_true(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_ceiling_a_position_below_the_overdraw_band() -> void:
	var wall_tile := Vector2i(2, 3)
	# y=220 is further south than the 16px overdraw band reaches (192-208).
	var position := Vector2(120.0, 220.0)

	assert_false(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_ceiling_a_position_north_of_the_wall() -> void:
	var wall_tile := Vector2i(2, 3)
	# y=160 is inside/north of the wall's own tile -- the ceiling front face
	# only ever reads as hanging down, never occludes anything north of it.
	var position := Vector2(120.0, 160.0)

	assert_false(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_ceiling_a_position_outside_its_column() -> void:
	var wall_tile := Vector2i(2, 3)
	# Same y as the first (passing) test, but x=200 is a full tile-width
	# outside wall_tile's own column (x=[96,144]).
	var position := Vector2(200.0, 200.0)

	assert_false(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_occludes_ceiling_at_the_exact_tile_bottom_boundary() -> void:
	var wall_tile := Vector2i(2, 3)
	var position := Vector2(120.0, 192.0) # exactly the wall's own tile_bottom

	assert_true(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))
```

Append to the same file, after the existing `test_draw_does_not_error_with_walls_and_a_fade_focus_present` function:

```gdscript
func test_draw_does_not_error_on_ceiling_plane_with_walls_and_a_fade_focus() -> void:
	var renderer := _make_renderer()
	renderer.set_active_plane(Level.Layer.CEILING)
	renderer.set_fade_focus(Vector2(24.0, 24.0))

	await get_tree().process_frame

	assert_true(true, "reached this point without erroring")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A20 "test_maze_renderer_occlusion"`
Expected: a parse/compile error (`wall_occludes_position_ceiling` doesn't exist yet), or the 6 new tests failing while the pre-existing ones still pass.

- [ ] **Step 3: Implement the mirrored occlusion check and per-plane wall drawing**

In `world/maze/maze_renderer.gd`, add this static function immediately after the existing `wall_occludes_position()` function:

```gdscript
## Ceiling-plane mirror of wall_occludes_position(): the ceiling variant's
## rendered block pokes `overdraw` pixels below its own tile into the tile
## south of it (front face hangs down instead of rising up -- see
## _draw_wall_ceiling()) -- same occlusion idiom, opposite direction.
static func wall_occludes_position_ceiling(wall_tile: Vector2i, position: Vector2, tile_size: int, overdraw: float) -> bool:
	var tile_left := float(wall_tile.x) * tile_size
	var tile_bottom := float(wall_tile.y) * tile_size + tile_size
	if position.x < tile_left or position.x > tile_left + tile_size:
		return false
	return position.y >= tile_bottom and position.y <= tile_bottom + overdraw
```

Then replace the existing `_draw_wall()` function entirely with these three functions:

```gdscript
## Draws one wall tile's block, dispatching to the plane-appropriate
## orientation -- see _draw_wall_ground()/_draw_wall_ceiling().
func _draw_wall(tile: Vector2i) -> void:
	if _active_plane == Level.Layer.GROUND:
		_draw_wall_ground(tile)
	else:
		_draw_wall_ceiling(tile)


## Ground-plane wall: front face anchored to the tile's own bottom edge,
## top face poking up into the tile north of it. Fades both faces together
## if this wall currently occludes fade_focus_position.
func _draw_wall_ground(tile: Vector2i) -> void:
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


## Ceiling-plane wall: mirrored -- front face anchored to the tile's own
## top edge, hanging down; top face pokes down into the tile south of it
## (tunnel visual rework Phase 2). Fades both faces together if this wall
## currently occludes fade_focus_position via the ceiling-mirrored check.
func _draw_wall_ceiling(tile: Vector2i) -> void:
	var alpha := wall_fade_alpha if wall_occludes_position_ceiling(tile, fade_focus_position, _tile_size, wall_overdraw_height) else 1.0
	var tile_left := tile.x * _tile_size
	var tile_top := tile.y * _tile_size
	var tile_bottom := tile_top + _tile_size
	var block_bottom := tile_bottom + wall_overdraw_height
	var front_face_bottom := tile_top + wall_front_face_height
	draw_rect(Rect2(tile_left, front_face_bottom, _tile_size, block_bottom - front_face_bottom),
		Color(wall_top_face_color, wall_top_face_color.a * alpha))
	draw_rect(Rect2(tile_left, tile_top, _tile_size, wall_front_face_height),
		Color(wall_front_face_color, wall_front_face_color.a * alpha))
```

Also update the class doc comment's last paragraph (currently ending "...and the ceiling-plane inverse wall treatment (front face hanging down instead of rising up) is a later phase, not yet built.") — replace that sentence with:

```
## and the ceiling-plane inverse wall treatment (front face hanging down
## instead of rising up) is implemented via _draw_wall_ceiling().
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A20 "test_maze_renderer_occlusion"`
Expected: `14/14 passed.` (8 pre-existing + 6 new)

- [ ] **Step 5: Run the full suite to check for regressions**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | tail -20`
Expected: same pass count as before this task plus 6, no new failures. (One pre-existing, unrelated flaky test — `test_open_ground_does_not_block_a_spawned_larva` in `tests/test_larva_hazards.gd` — may intermittently fail; a known, already-present flake, not something to chase here.)

- [ ] **Step 6: Headless boot check**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"`
Expected: no output (clean boot).

- [ ] **Step 7: Import + commit**

```bash
~/.local/bin/godot --headless --path . --import
git add world/maze/maze_renderer.gd tests/test_maze_renderer_occlusion.gd
git commit -m "MazeRenderer: mirrored ceiling-plane wall rendering + occlusion fade"
```

---

### Task 2: `FloorRenderer` + `GroundLayer` dim shader — floor moves out of `MazeRenderer`

**Files:**
- Create: `assets/shaders/ground_dim.gdshader`
- Create: `world/ground_layer.gd`
- Create: `world/maze/floor_renderer.gd`
- Modify: `world/maze/maze_renderer.gd`
- Modify: `world/level.tscn`
- Modify: `world/level.gd`
- Test: `tests/test_ground_layer.gd` (new)
- Test: `tests/test_floor_renderer.gd` (new)
- Test: `tests/test_maze_renderer_plane.gd` (modify)
- Test: `tests/test_level_plane_focus.gd` (add to it)

**Interfaces:**
- Consumes: nothing from Task 1 directly (this task only touches floor rendering; Task 1 only touched wall rendering in the same file).
- Produces: `GroundLayer.set_dimmed(dimmed: bool) -> void`, `GroundLayer.GroundDimShader` (const), `FloorRenderer.setup(maze: MazeData, tile_size: int) -> void`. Task 3 depends on `Level._ground_layer` (an `@onready var` this task adds) to reparent ground-only entities onto.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_ground_layer.gd`:

```gdscript
extends GutTest
## GroundLayer (tunnel visual rework Phase 2): a CanvasGroup carrying the
## desaturate/darken shader for the "hazy background" read while the
## player is on the ceiling. set_dimmed() lazily creates the material on
## _ready() and just flips one uniform -- no ref-counting needed (unlike
## OutlineFx's outline toggle), since only Level's own plane-focus refresh
## ever calls this for one node.

func _make_ground_layer() -> GroundLayer:
	var layer := GroundLayer.new()
	add_child_autofree(layer)
	return layer


func test_ready_creates_the_shader_material() -> void:
	var layer := _make_ground_layer()

	var mat := layer.material as ShaderMaterial
	assert_not_null(mat)
	assert_eq(mat.shader, GroundLayer.GroundDimShader)


func test_set_dimmed_true_sets_the_shader_parameter() -> void:
	var layer := _make_ground_layer()

	layer.set_dimmed(true)

	var mat := layer.material as ShaderMaterial
	assert_true(mat.get_shader_parameter("dim_enabled"))


func test_set_dimmed_false_clears_the_shader_parameter() -> void:
	var layer := _make_ground_layer()
	layer.set_dimmed(true)

	layer.set_dimmed(false)

	var mat := layer.material as ShaderMaterial
	assert_false(mat.get_shader_parameter("dim_enabled"))
```

Create `tests/test_floor_renderer.gd`:

```gdscript
extends GutTest
## FloorRenderer (tunnel visual rework Phase 2): draws just the maze's open
## floor tiles, split out of MazeRenderer so GroundLayer can dim it
## independently of the (now wall-only) MazeRenderer. No pixel assertions
## -- this project's own established pattern (see test_maze_renderer_plane.gd)
## -- just that setup() doesn't error against a real maze once the engine's
## own redraw cycle actually calls _draw() (never call _draw() directly --
## draw_rect() requires an active redraw pass).

func test_setup_does_not_error_with_a_real_maze() -> void:
	var renderer := FloorRenderer.new()
	add_child_autofree(renderer)
	var maze := MazeGenerator.generate(3, 3, 1)

	renderer.setup(maze, 48)
	await renderer.get_tree().process_frame

	assert_true(true, "reached this point without erroring")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A10 "test_ground_layer\|test_floor_renderer"`
Expected: parse/compile errors — `GroundLayer` and `FloorRenderer` don't exist yet.

- [ ] **Step 3: Create the shader**

Create `assets/shaders/ground_dim.gdshader`:

```glsl
shader_type canvas_item;

// Desaturate + darken pass for GroundLayer's "hazy background" read while
// viewed from the ceiling (tunnel visual rework Phase 2) -- no blur
// convolution, matching the design doc's own recommendation to start with
// the cheaper version and only reach for a true blur pass if playtesting
// shows it's needed. dim_enabled is a plain on/off switch, not a strength
// dial -- GroundLayer is either the background (dimmed) or the plane in
// focus (undimmed), never a partial blend between the two.
uniform float saturation : hint_range(0.0, 1.0) = 0.6;
uniform float brightness : hint_range(0.0, 1.0) = 0.75;
uniform bool dim_enabled = false;

void fragment() {
	// No early `return` in fragment() -- this project's renderer rejects it
	// (see outline.gdshader's identical note); every branch funnels into
	// one COLOR assignment instead.
	vec4 tex_color = texture(TEXTURE, UV);
	if (dim_enabled) {
		float luminance = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
		vec3 desaturated = mix(vec3(luminance), tex_color.rgb, saturation);
		COLOR = vec4(desaturated * brightness, tex_color.a);
	} else {
		COLOR = tex_color;
	}
}
```

- [ ] **Step 4: Create `GroundLayer`**

Create `world/ground_layer.gd`:

```gdscript
class_name GroundLayer
extends CanvasGroup
## Everything ground-resident that should read as a hazy background layer
## while the player is on the ceiling (tunnel visual rework Phase 2, design:
## docs/superpowers/specs/2026-07-14-tunnel-visual-rework-design.md) --
## FloorRenderer's floor tiles, hazard markers (pits/water), larvae, and
## items all get parented here (see Level's spawn methods). A CanvasGroup
## flattens all of that into one texture so a single shader pass can
## desaturate/darken it as a unit, rather than tinting each child
## individually. Plane-aware entities (Player/Enemy and anything they can
## place on either plane) stay outside this node -- they already have
## their own per-entity dimming (Level._refresh_plane_focus's body_alpha),
## a different question ("is this specific entity on the off-plane") from
## "is this static ground content in the background right now." Both
## Centipede types stay outside this node too, for a different reason:
## a Centipede's body is the same width as the tunnel itself, so it must
## read identically regardless of plane, unlike a loose larva or item.

const GroundDimShader := preload("res://assets/shaders/ground_dim.gdshader")

var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = GroundDimShader
	material = _material


## Toggles the hazy-background treatment -- Level calls this from
## _refresh_plane_focus() whenever the focus plane (the player's own)
## changes: dimmed while CEILING is in focus (the ground is background),
## full clarity while GROUND is in focus (the ground is what's underfoot).
func set_dimmed(dimmed: bool) -> void:
	_material.set_shader_parameter("dim_enabled", dimmed)
```

- [ ] **Step 5: Create `FloorRenderer`**

Create `world/maze/floor_renderer.gd`:

```gdscript
class_name FloorRenderer
extends Node2D
## Draws just the maze's open floor tiles (tunnel visual rework Phase 2) --
## split out of MazeRenderer, which now draws only walls, so this can live
## inside GroundLayer and get desaturated/darkened as a unit while
## MazeRenderer's walls (crisp foreground) stay outside it. Always draws
## the one true ground floor_color -- the old per-plane ceiling_floor_color
## recolor is retired: a real background layer that dims independently
## makes a second recolor redundant. Redrawn on setup() and whenever
## Level's own wall-editing calls (dev_remove_wall_at, collapse_tile_at)
## already redraw MazeRenderer -- no per-frame redraw needed, since floor
## geometry has no per-frame-changing state (no fade dependency, unlike
## MazeRenderer's walls).

var _maze: MazeData
var _tile_size := 48
var floor_color := Color(0.17, 0.15, 0.13)


func setup(maze: MazeData, tile_size: int) -> void:
	_maze = maze
	_tile_size = tile_size
	queue_redraw()


func _draw() -> void:
	if _maze == null:
		return
	for y in _maze.height:
		for x in _maze.width:
			if _maze.is_open(x, y):
				draw_rect(Rect2(x * _tile_size, y * _tile_size, _tile_size, _tile_size), floor_color)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A10 "test_ground_layer\|test_floor_renderer"`
Expected: `3/3 passed.` for `test_ground_layer.gd`, `1/1 passed.` for `test_floor_renderer.gd`.

- [ ] **Step 7: Remove floor-drawing from `MazeRenderer`**

In `world/maze/maze_renderer.gd`:

Remove these two lines entirely:

```gdscript
var floor_color := Color(0.17, 0.15, 0.13)
var ceiling_floor_color := Color(0.13, 0.17, 0.24)
```

Replace the `_draw()` function with:

```gdscript
func _draw() -> void:
	if _maze == null:
		return
	for y in _maze.height:
		for x in _maze.width:
			if not _maze.is_open(x, y):
				_draw_wall(Vector2i(x, y))
	_draw_grid_lines()
```

Replace the class doc comment's second paragraph (the one starting "## Ceiling/plane mechanics rework: open tiles render in floor_color or...") with:

```gdscript
##
## Tunnel visual rework Phase 2: floor rendering (including the old
## per-plane ceiling_floor_color recolor) has moved to FloorRenderer/
## GroundLayer, which reads "which plane am I on" via dimming instead of a
## color swap -- see docs/superpowers/specs/2026-07-14-tunnel-visual-
## rework-design.md. This class now draws walls only. set_active_plane()
## still drives which way a wall's front face renders (_draw_wall_ground()
## vs _draw_wall_ceiling()).
```

- [ ] **Step 8: Update `test_maze_renderer_plane.gd`**

Replace the file's header comment (the block starting `## MazeRenderer's per-plane floor color...`) with:

```gdscript
extends GutTest
## MazeRenderer's per-plane wall orientation (tunnel visual rework Phase 2):
## _active_plane now drives which way a wall's front face renders (see
## _draw_wall_ground()/_draw_wall_ceiling()) rather than a floor recolor --
## floor rendering moved to FloorRenderer/GroundLayer, which handles "which
## plane am I on" via dimming instead (see test_ground_layer.gd,
## test_level_plane_focus.gd).
```

Remove the `test_floor_and_ceiling_colors_are_distinct()` function entirely (the field it asserts on, `ceiling_floor_color`, no longer exists).

- [ ] **Step 9: Wire `GroundLayer`/`FloorRenderer` into `level.tscn`**

Replace the entire contents of `world/level.tscn` with:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://world/level.gd" id="1_level"]
[ext_resource type="Script" path="res://world/maze/maze_renderer.gd" id="2_renderer"]
[ext_resource type="Script" path="res://world/ground_layer.gd" id="3_ground_layer"]
[ext_resource type="Script" path="res://world/maze/floor_renderer.gd" id="4_floor_renderer"]

[node name="Level" type="Node2D"]
script = ExtResource("1_level")

[node name="CanvasModulate" type="CanvasModulate" parent="."]
color = Color(0.05, 0.05, 0.07, 1)

[node name="GroundLayer" type="CanvasGroup" parent="."]
script = ExtResource("3_ground_layer")

[node name="FloorRenderer" type="Node2D" parent="GroundLayer"]
script = ExtResource("4_floor_renderer")

[node name="Renderer" type="Node2D" parent="."]
script = ExtResource("2_renderer")

[node name="Walls" type="StaticBody2D" parent="."]
collision_layer = 1
collision_mask = 0

[node name="Occluders" type="Node2D" parent="."]

[node name="Entities" type="Node2D" parent="."]

[node name="SenseLayer" type="CanvasLayer" parent="."]
follow_viewport_enabled = true
layer = 1
```

`GroundLayer` (with `FloorRenderer` inside it) now draws first, then `Renderer` (walls only) on top of it, then `Walls`/`Occluders`/`Entities`/`SenseLayer` unchanged — preserving the existing "entities always draw on top" guarantee while adding the new layer underneath the walls.

- [ ] **Step 10: Wire `Level` to set up and dim the new nodes**

In `world/level.gd`, add these two `@onready` vars immediately after the existing `@onready var _renderer: MazeRenderer = $Renderer` line:

```gdscript
@onready var _ground_layer: GroundLayer = $GroundLayer
@onready var _floor_renderer: FloorRenderer = $GroundLayer/FloorRenderer
```

In `build()`, immediately after the existing `_renderer.setup(maze, TILE_SIZE)` line, add:

```gdscript
	_floor_renderer.setup(maze, TILE_SIZE)
```

In `dev_remove_wall_at()`, immediately after the existing `_renderer.queue_redraw()` line, add:

```gdscript
	_floor_renderer.queue_redraw()
```

In `collapse_tile_at()`, immediately after the existing `_renderer.queue_redraw()` line, add:

```gdscript
	_floor_renderer.queue_redraw()
```

In `_refresh_plane_focus()`, immediately after the existing `var focus_plane := PlaneComponent.effective_plane(player)` line, add:

```gdscript
	_ground_layer.set_dimmed(focus_plane == Layer.CEILING)
```

- [ ] **Step 11: Write the failing Level-integration tests**

Append to `tests/test_level_plane_focus.gd`:

```gdscript
func test_refresh_plane_focus_dims_ground_layer_when_player_is_on_ceiling() -> void:
	var level := _make_level()
	var player_plane := level.player.get_node("PlaneComponent") as PlaneComponent
	player_plane.current_plane = Level.Layer.CEILING

	level._refresh_plane_focus()

	var mat := level._ground_layer.material as ShaderMaterial
	assert_true(mat.get_shader_parameter("dim_enabled"), "ground is background while the player is on the ceiling")


func test_refresh_plane_focus_keeps_ground_layer_undimmed_when_player_is_on_ground() -> void:
	var level := _make_level()

	level._refresh_plane_focus() # default GROUND

	var mat := level._ground_layer.material as ShaderMaterial
	assert_false(mat.get_shader_parameter("dim_enabled"), "ground is the plane in focus, not background")
```

- [ ] **Step 12: Run tests to verify they pass**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A15 "test_level_plane_focus\|test_maze_renderer_plane"`
Expected: `test_level_plane_focus.gd` shows `7/7 passed.` (5 pre-existing + 2 new); `test_maze_renderer_plane.gd` shows `3/3 passed.`

- [ ] **Step 13: Run the full suite to check for regressions**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | tail -20`
Expected: no new failures beyond the known pre-existing `test_larva_hazards.gd` flake.

- [ ] **Step 14: Headless boot check**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"`
Expected: no output (clean boot — this is the check that would catch a shader compile failure, per this project's own established gotcha).

- [ ] **Step 15: Import + commit**

```bash
~/.local/bin/godot --headless --path . --import
git add assets/shaders/ground_dim.gdshader world/ground_layer.gd world/maze/floor_renderer.gd \
	world/maze/maze_renderer.gd world/level.tscn world/level.gd \
	tests/test_ground_layer.gd tests/test_ground_layer.gd.uid \
	tests/test_floor_renderer.gd tests/test_floor_renderer.gd.uid \
	tests/test_maze_renderer_plane.gd tests/test_level_plane_focus.gd
git commit -m "GroundLayer/FloorRenderer: floor dim-on-ceiling, retire ceiling_floor_color"
```

---

### Task 3: Reparent ground-only content under `GroundLayer`

**Files:**
- Modify: `world/level.gd`
- Test: `tests/test_level_hazard_helpers.gd` (add to it)
- Test: `tests/test_level_ground_layer_parenting.gd` (new)

**Interfaces:**
- Consumes: `Level._ground_layer` (added in Task 2).
- Produces: nothing later in this plan depends on this.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_level_hazard_helpers.gd`:

```gdscript
func test_pit_marker_is_parented_under_ground_layer() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]

	level.set_pit_at(open_cell, true)

	var marker: Node2D = level._pit_nodes[open_cell]
	assert_eq(marker.get_parent(), level._ground_layer)


func test_water_marker_is_parented_under_ground_layer() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]

	level.set_water_at(open_cell, true)

	var marker: Node2D = level._water_nodes[open_cell]
	assert_eq(marker.get_parent(), level._ground_layer)
```

Create `tests/test_level_ground_layer_parenting.gd`:

```gdscript
extends GutTest
## Ground-only content parenting (tunnel visual rework Phase 2): larvae,
## world items, and hazard markers (see test_level_hazard_helpers.gd) get
## parented under GroundLayer instead of Entities/Level directly, so they
## read as part of the dimmable "hazy background" while the player is on
## the ceiling (see docs/superpowers/specs/2026-07-14-tunnel-visual-rework-
## design.md). Player/Enemy (plane-aware, dimmed individually via
## body_alpha instead) stay under Entities, unaffected -- and so do both
## Centipede types (correction, 2026-07-14): a Centipede's body is the same
## width as the tunnel itself, so it must read identically regardless of
## plane, unlike a loose larva or item -- dimming it as "background" would
## be wrong.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_spawned_larva_is_parented_under_ground_layer() -> void:
	var level := _make_level()
	var larvae := level.get_tree().get_nodes_in_group("larvae")
	assert_gt(larvae.size(), 0, "level.build() seeds at least one larva by default")
	assert_eq((larvae[0] as Node2D).get_parent(), level._ground_layer)


func test_spawned_world_item_is_parented_under_ground_layer() -> void:
	var level := _make_level()
	var items := level.get_tree().get_nodes_in_group("world_items")
	assert_gt(items.size(), 0, "level.build() seeds ITEM_SPAWN_COUNT items by default")
	assert_eq((items[0] as Node2D).get_parent(), level._ground_layer)


func test_spawned_centipede_stays_parented_under_entities_not_ground_layer() -> void:
	var level := _make_level()
	var centipedes := level.get_tree().get_nodes_in_group("centipedes")
	if centipedes.is_empty():
		pending("no valid chain existed on this maze seed -- not exercised this run")
		return
	assert_eq((centipedes[0] as Node2D).get_parent(), level._entities,
		"a Centipede's body spans the tunnel width -- it must read the same on both planes, not dim as background")


func test_centipede_express_rider_stays_parented_under_entities_not_ground_layer() -> void:
	var level := _make_level()
	var entry: Vector2i = level.maze.open_cells()[0]

	level.spawn_centipede_express_rider(entry, Vector2i.RIGHT)

	var riders := level.get_tree().get_nodes_in_group("centipede_express_riders")
	assert_eq(riders.size(), 1)
	assert_eq((riders[0] as Node2D).get_parent(), level._entities)


func test_player_and_enemy_stay_parented_under_entities() -> void:
	var level := _make_level()
	assert_eq(level.player.get_parent(), level._entities)
	assert_eq(level.enemy.get_parent(), level._entities)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A10 "test_level_hazard_helpers\|test_level_ground_layer_parenting"`
Expected: the two new `test_level_hazard_helpers.gd` assertions and the `larva`/`world_item` assertions in `test_level_ground_layer_parenting.gd` fail (everything is currently parented under `Entities`/`Level` directly, not `_ground_layer`); the two Centipede tests and the player/enemy test already pass as written (nothing changes for them) — they're here as regression guards against a future change accidentally moving Centipedes into `GroundLayer`.

- [ ] **Step 3: Reparent the spawn call sites**

In `world/level.gd`:

In `_spawn_pit_marker()`, change:
```gdscript
	add_child(poly)
```
to:
```gdscript
	_ground_layer.add_child(poly)
```

In `_spawn_water_marker()`, change:
```gdscript
	add_child(poly)
```
to:
```gdscript
	_ground_layer.add_child(poly)
```

In `_spawn_pickup_at()`, change:
```gdscript
	_entities.add_child(pickup)
```
to:
```gdscript
	_ground_layer.add_child(pickup)
```

Leave `spawn_centipede_express_rider()` and `_seed_centipedes()` untouched — both Centipede types stay parented under `_entities` (see this task's header note on why).

In `_spawn_larva_at()`, change:
```gdscript
	_entities.add_child(larva)
```
to:
```gdscript
	_ground_layer.add_child(larva)
```

Leave `_spawn_entities()` (player/enemy) untouched — they stay under `_entities`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A15 "test_level_hazard_helpers\|test_level_ground_layer_parenting"`
Expected: `test_level_hazard_helpers.gd` shows `21/21 passed.` (19 pre-existing + 2 new); `test_level_ground_layer_parenting.gd` shows `5/5 passed.` (or `4/5 passed, 1 pending` if this maze seed had no valid Centipede chain).

- [ ] **Step 5: Run the full suite to check for regressions**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | tail -20`
Expected: no new failures beyond the known pre-existing `test_larva_hazards.gd` flake. Pay particular attention to any test that assumed larvae/items were children of `Entities` — none were found in this plan's own research (`grep` across `tests/*.gd` for `_entities`/`$Entities`/`Entities` turned up no such assumption), but a regression here would show up as a new failure in this run.

- [ ] **Step 6: Headless boot check**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"`
Expected: no output (clean boot).

- [ ] **Step 7: Import + commit**

```bash
~/.local/bin/godot --headless --path . --import
git add world/level.gd tests/test_level_hazard_helpers.gd \
	tests/test_level_ground_layer_parenting.gd tests/test_level_ground_layer_parenting.gd.uid
git commit -m "Level: reparent ground-only content (larvae, items, hazards) under GroundLayer"
```

- [ ] **Step 8: Manual playtest verification**

This phase is visual-only in its ultimate effect (no automated test renders pixels) — actually launch the game (`~/.local/bin/godot --path . res://world/world.tscn`), transition to the ceiling plane, and confirm: ceiling walls read as hanging down (mirrored from the ground's rising-up walls), and the floor below reads as a hazy/duller background rather than a flat recolor. This step doesn't get a checkbox for "expected output" the way the others do — it's a subjective look-and-feel call for a human to make.

---

### Task 4: Enemy's off-plane dimming switches from alpha fade to hazy/desaturate

**Files:**
- Modify: `assets/shaders/outline.gdshader`
- Modify: `components/outline_fx.gd`
- Modify: `world/level.gd`
- Test: `tests/test_outline_fx.gd` (add to it)
- Test: `tests/test_level_plane_focus.gd` (modify)

**Interfaces:**
- Consumes: nothing from Tasks 1-3.
- Produces: `OutlineFx.set_dimmed(sprite: CanvasItem, dimmed: bool) -> void`. Nothing later in this plan depends on this — this is the last task.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_outline_fx.gd`:

```gdscript
func test_set_dimmed_true_sets_the_shader_uniform() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_dimmed(sprite, true)

	var mat := sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.get_shader_parameter("dim_enabled"))


func test_set_dimmed_on_null_sprite_is_a_noop() -> void:
	OutlineFx.set_dimmed(null, true) # must not error
	assert_true(true, "reached this point without erroring")


## Mirrors test_set_body_alpha_back_to_neutral_releases_the_material's own
## rationale: the shader must actually come off once dimmed becomes false
## and nothing else needs the material, not just numerically neutralize
## while staying attached.
func test_set_dimmed_back_to_false_releases_the_material() -> void:
	var sprite := _make_sprite()
	OutlineFx.set_dimmed(sprite, true) # e.g. off the player's plane
	assert_not_null(sprite.material)

	OutlineFx.set_dimmed(sprite, false) # e.g. back on the same plane

	assert_null(sprite.material,
		"back to neutral -- the shader comes off entirely, not just numerically neutral")


func test_set_dimmed_false_on_an_untouched_sprite_never_creates_a_material() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_dimmed(sprite, false)

	assert_null(sprite.material, "the common case (never off-plane) never even touches the shader")


func test_set_dimmed_reuses_the_same_material_set_outline_uses() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_outline(sprite, true, Color.RED)
	var mat_after_outline := sprite.material
	OutlineFx.set_dimmed(sprite, true)
	var mat_after_dim := sprite.material

	assert_eq(mat_after_outline, mat_after_dim, "one shared material, not a second one stacked on")


## Verifies _release_if_neutral() now checks dim_enabled too, not just
## outline_active/body_alpha -- otherwise a sprite that's dimmed but
## otherwise neutral (no outline, body_alpha at 1.0) would have its
## material incorrectly stripped, silently losing the dim visual.
func test_set_dimmed_true_keeps_the_material_even_though_outline_and_body_alpha_are_neutral() -> void:
	var sprite := _make_sprite()

	OutlineFx.set_dimmed(sprite, true)

	assert_not_null(sprite.material, "dim_enabled alone is enough reason to keep the material attached")
```

Replace the two body_alpha-based dimming assertions in `tests/test_level_plane_focus.gd`. First, in `test_refresh_plane_focus_dims_the_enemy_when_only_it_is_on_the_ceiling()`, replace:

```gdscript
	var mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), Level.OFF_PLANE_ALPHA, 0.001,
		"enemy is off the player's plane, so it dims")
```

with:

```gdscript
	var mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.get_shader_parameter("dim_enabled"), "enemy is off the player's plane, so it reads hazy/desaturated")
```

Second, in `test_plane_changed_event_triggers_a_focus_refresh()`, replace:

```gdscript
	var mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), Level.OFF_PLANE_ALPHA, 0.001)
```

with:

```gdscript
	var mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.get_shader_parameter("dim_enabled"))
```

The other four tests in that file (`test_refresh_plane_focus_keeps_full_brightness_when_planes_match` and the two Camouflage guardrail tests) need no changes — they don't assert on `body_alpha`'s off-plane value.

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A10 "test_outline_fx\|test_level_plane_focus"`
Expected: `test_outline_fx.gd` fails to parse (`set_dimmed` doesn't exist yet); `test_level_plane_focus.gd`'s two modified tests fail (`dim_enabled` doesn't exist on the shader yet either).

- [ ] **Step 3: Add the desaturate uniforms and math to `outline.gdshader`**

Replace the entire contents of `assets/shaders/outline.gdshader` with:

```glsl
shader_type canvas_item;

// Standard alpha-edge outline: if this texel is (near-)transparent but a
// same-distance neighbour (8-tap: 4 cardinal + 4 diagonal, so corners get
// full coverage too) is opaque, paint outline_color instead. body_alpha
// dims normal body pixels only — kept independent of outline_color's own
// alpha so a caller (Camouflage) can fade the body to near-invisible while
// the outline stays fully visible, which node `modulate` can't do (it
// multiplies everything this shader outputs, outline included).
//
// dim_enabled/saturation/brightness (tunnel visual rework Phase 2): the
// same desaturate+darken formula GroundLayer's ground_dim.gdshader uses
// for "hazy background" content, merged into this shader instead of a
// second material — a CanvasItem can only ever hold one material, and
// Player/Enemy sprites already depend on this one for outline/Camouflage.
// Applies to the body color only, never outline_color (a deliberately
// chosen flat color, not sampled texture content, so there's nothing to
// desaturate).
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 4.0) = 2.0;
uniform bool outline_enabled = true;
uniform float body_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float saturation : hint_range(0.0, 1.0) = 0.6;
uniform float brightness : hint_range(0.0, 1.0) = 0.75;
uniform bool dim_enabled = false;

void fragment() {
	// No early `return` in fragment() — this project's renderer rejects it
	// ("SHADER ERROR: Using 'return' in the 'fragment' processor function
	// is incorrect."), silently failing the whole shader's compilation.
	// Every branch below funnels into one COLOR assignment instead.
	vec4 tex_color = texture(TEXTURE, UV);
	vec3 body_rgb = tex_color.rgb;
	if (dim_enabled) {
		float luminance = dot(body_rgb, vec3(0.299, 0.587, 0.114));
		body_rgb = mix(vec3(luminance), body_rgb, saturation) * brightness;
	}
	if (tex_color.a > 0.5 || !outline_enabled) {
		COLOR = vec4(body_rgb, tex_color.a * body_alpha);
	} else {
		vec2 texel = outline_width / vec2(textureSize(TEXTURE, 0));
		float neighbor_alpha = 0.0;
		neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, 0.0)).a;
		neighbor_alpha += texture(TEXTURE, UV - vec2(texel.x, 0.0)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(0.0, texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV - vec2(0.0, texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV + texel).a;
		neighbor_alpha += texture(TEXTURE, UV - texel).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, -texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(-texel.x, texel.y)).a;
		COLOR = neighbor_alpha > 0.0 ? outline_color : vec4(body_rgb, tex_color.a * body_alpha);
	}
}
```

- [ ] **Step 4: Add `OutlineFx.set_dimmed()` and update `_release_if_neutral()`**

In `components/outline_fx.gd`, add this function immediately after `set_body_alpha()`:

```gdscript
## Sets the shader's dim_enabled uniform directly (tunnel visual rework
## Phase 2) -- no ref-counting, same rationale as set_body_alpha: only
## one caller (Level._refresh_plane_focus) ever decides this per sprite,
## so the last call wins.
static func set_dimmed(sprite: CanvasItem, dimmed: bool) -> void:
	if sprite == null:
		return
	# Mirrors set_body_alpha's fast path: nothing to do if there's no
	# material yet and this call wouldn't need one either.
	if not dimmed and (sprite.material as ShaderMaterial == null or (sprite.material as ShaderMaterial).shader != OutlineShader):
		return
	var mat := _material_of(sprite)
	mat.set_shader_parameter("dim_enabled", dimmed)
	_release_if_neutral(sprite)
```

Replace `_release_if_neutral()` entirely with:

```gdscript
## Once neither effect this shader provides is actually doing anything
## (outline off for every caller, body_alpha back to its neutral 1.0,
## AND dim_enabled false), detaches the material entirely and restores
## `sprite.material` to null -- every sprite this project ever applies
## the outline shader to starts with no material of its own. Leaving a
## "neutral" ShaderMaterial permanently attached instead (found via
## playtest: a ceiling-plane transition dims the off-plane spider via
## set_body_alpha(), and the shader visibly never came back off even
## once alpha returned to 1.0) takes the sprite out of the engine's
## default per-item rendering path for good, for no reason -- the
## numeric effect is already fully neutral, so there's nothing left for
## a lingering material to be doing.
static func _release_if_neutral(sprite: CanvasItem) -> void:
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != OutlineShader:
		return
	var id := sprite.get_instance_id()
	var outline_active: bool = _ref_counts.get(id, 0) > 0
	# get_shader_parameter() returns null (not the shader's own declared
	# default) for a uniform this material has never explicitly set --
	# an unset body_alpha is still the neutral 1.0, just not overridden yet.
	var alpha_param: Variant = mat.get_shader_parameter("body_alpha")
	var alpha: float = alpha_param if alpha_param != null else 1.0
	var dim_param: Variant = mat.get_shader_parameter("dim_enabled")
	var dimmed: bool = dim_param if dim_param != null else false
	if not outline_active and is_equal_approx(alpha, 1.0) and not dimmed:
		sprite.material = null
```

- [ ] **Step 5: Wire `Level._refresh_plane_focus()` to use `set_dimmed` instead of `set_body_alpha`**

In `world/level.gd`, remove this constant and its doc comment entirely:

```gdscript
## Ceiling/plane mechanics rework: body_alpha for whichever of Player/Enemy
## is off the other's plane — "less in focus," per the user's own framing
## during brainstorming. Deliberately scoped to just these two (the only
## entities that track a plane at all); larvae/hatchlings/decoys/traps
## always render at full brightness regardless of plane (design's explicit
## out-of-scope call).
const OFF_PLANE_ALPHA := 0.35
```

Replace the doc comment above `_refresh_plane_focus()` (the one starting `## Dims whichever of Player/Enemy is off the other's plane via the shared`) with:

```gdscript
## Dims whichever of Player/Enemy is off the other's plane via the shared
## outline shader's dim_enabled uniform (tunnel visual rework Phase 2 --
## previously a flat body_alpha fade, switched to match GroundLayer's own
## hazy/desaturated "background" look for visual consistency) -- the
## floor dim (above, GroundLayer) tells you which plane *you're* on; this
## tells you which other spider is or isn't reachable from here.
```

In `_refresh_plane_focus()`, replace the loop's last two lines:

```gdscript
		var alpha := 1.0 if PlaneComponent.effective_plane(node) == focus_plane else OFF_PLANE_ALPHA
		OutlineFx.set_body_alpha(vis, alpha)
```

with:

```gdscript
		OutlineFx.set_dimmed(vis, PlaneComponent.effective_plane(node) != focus_plane)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | grep -A15 "test_outline_fx\|test_level_plane_focus"`
Expected: `test_outline_fx.gd` shows `18/18 passed.` (12 pre-existing + 6 new); `test_level_plane_focus.gd` shows `7/7 passed.` (unchanged count from Task 2, since Task 4 modifies existing tests rather than adding new ones).

- [ ] **Step 7: Run the full suite to check for regressions**

Run: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit 2>&1 | tail -20`
Expected: no new failures beyond the known pre-existing `test_larva_hazards.gd` flake. Double-check nothing else in the suite reads `Level.OFF_PLANE_ALPHA` (a stale reference would now be a parse error, not a silent pass) — this plan's own research found only `world/level.gd` and `tests/test_level_plane_focus.gd` reference it, both handled by this task.

- [ ] **Step 8: Headless boot check**

Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"`
Expected: no output (clean boot — this is the check that would catch a shader compile failure in the merged `outline.gdshader`, per this project's own established gotcha).

- [ ] **Step 9: Import + commit**

```bash
~/.local/bin/godot --headless --path . --import
git add assets/shaders/outline.gdshader components/outline_fx.gd world/level.gd \
	tests/test_outline_fx.gd tests/test_level_plane_focus.gd
git commit -m "Enemy off-plane dimming: switch from flat alpha fade to hazy/desaturate"
```

- [ ] **Step 10: Manual playtest verification**

Actually launch the game (`~/.local/bin/godot --path . res://world/world.tscn`), get Player and Enemy onto different planes (e.g. transition to the ceiling, or use the dev tools if available), and confirm Enemy reads as hazy/desaturated rather than merely more transparent. This step doesn't get a checkbox for "expected output" the way the others do — it's a subjective look-and-feel call for a human to make.
