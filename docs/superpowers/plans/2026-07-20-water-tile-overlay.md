# Water Tile Visual Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat-color flooded-tile marker with a two-layer visual: a static "wet floor" base texture and a semi-transparent, slowly-scrolling water-overlay texture on top.

**Architecture:** A flooded tile's marker becomes a small container `Node2D` with two children of a new `WaterTileLayer` class, each drawing one texture across the tile's bounds via `draw_texture_rect` (the same idiom `FloorRenderer`/`MazeRenderer` already use). The base child reuses `GroundLayer`'s existing shared `dim_material()`; the overlay child gets a new `ShaderMaterial` (`GroundLayer.water_overlay_material()`) backed by a new `water_overlay.gdshader` that adds `TIME`-driven UV scroll on top of the same desaturate/darken logic `ground_dim.gdshader` already has, so it still participates in the ceiling/ground dim toggle.

**Tech Stack:** Godot 4.7 (GDScript, `canvas_item` shaders), GUT test framework.

## Global Constraints

- Godot binary: `~/.local/bin/godot`. All headless commands below run from the repo root (`/home/e3h1x/workspace/burrow/.claude/worktrees/art-pipeline-design`).
- No early `return` inside any `fragment()` — this project's renderer rejects it outright (confirmed failure mode: `outline.gdshader`, see `ground_dim.gdshader`'s doc comment). Every branch must funnel into one `COLOR` assignment.
- After touching any `.gdshader` file, a throwaway headless scene must actually instantiate the material and check for `SHADER ERROR` in output — GUT tests and `--import` never trigger real shader compilation, so a broken shader can silently pass both. Delete the scratch `.gd`/`.tscn` (and its `.gd.uid` sidecar) before committing — never leave scratch files in `git status`.
- New `.gd` files leave a `.gd.uid` sidecar; new binary assets leave a `.png.import` sidecar. Both must be committed — check `git status` after every asset/script-adding step.
- Existing test style: `GutTest` subclasses, `add_child_autofree()` for node lifecycle, `assert_eq`/`assert_true`/`assert_false`/`assert_not_null`. Match it exactly — no new assertion helpers.
- GUT suite command: `~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`. Known pre-existing flake: `test_larva_hazards.gd` (unrelated to this work — don't chase it here unless a clean checkout also fails).

---

### Task 1: Import the two textures, retire the old placeholder

**Files:**
- Create: `assets/textures/wet_floor_material.png`
- Create: `assets/textures/water_overlay_material.png`
- Delete: `assets/textures/water_material.png`
- Modify: `spritecook-assets.json`
- Delete (after use): `scratch_tile_check.gd`, `scratch_tile_check_wet_floor_material.png`, `scratch_tile_check_water_overlay_material.png`

**Interfaces:**
- Produces: `res://assets/textures/wet_floor_material.png`, `res://assets/textures/water_overlay_material.png` — the two texture paths every later task preloads.

- [ ] **Step 1: Copy the two source images into the project**

The two candidate textures were already downloaded during design review to
`/home/e3h1x/.claude/jobs/9ecd8b97/tmp/water_a.png` (wet floor,
SpriteCook asset `167258df-a3ef-4e7a-b9bc-b391a113825c`) and
`/home/e3h1x/.claude/jobs/9ecd8b97/tmp/water_b.png` (water overlay,
SpriteCook asset `2bd08a56-f480-4296-b8f8-5c83af7210b7`). Copy them in
under their final names:

```bash
cp /home/e3h1x/.claude/jobs/9ecd8b97/tmp/water_a.png assets/textures/wet_floor_material.png
cp /home/e3h1x/.claude/jobs/9ecd8b97/tmp/water_b.png assets/textures/water_overlay_material.png
rm assets/textures/water_material.png assets/textures/water_material.png.import
```

If those temp files no longer exist (job scratch dirs are cleaned up),
re-fetch via the SpriteCook MCP's `get_asset_metadata` or
`list_recent_assets` for the two asset IDs above to get fresh signed URLs,
then `curl -s -o <dest> "<signed_url>"`.

- [ ] **Step 2: Import and confirm sidecars**

```bash
~/.local/bin/godot --headless --path . --import
git status --short assets/textures/
```

Expected: `wet_floor_material.png`, `wet_floor_material.png.import`,
`water_overlay_material.png`, `water_overlay_material.png.import` all show
as new/untracked; `water_material.png` and `water_material.png.import`
show as deleted.

- [ ] **Step 3: Verify both textures tile seamlessly**

Write `scratch_tile_check.gd` at the repo root:

```gdscript
extends SceneTree

func _init() -> void:
	for texture_name in ["wet_floor_material", "water_overlay_material"]:
		var src := Image.new()
		var err := src.load("res://assets/textures/%s.png" % texture_name)
		if err != OK:
			printerr("Failed to load %s: %s" % [texture_name, err])
			continue
		src.convert(Image.FORMAT_RGBA8)
		var w := src.get_width()
		var h := src.get_height()
		var composite := Image.create(w * 3, h * 3, false, Image.FORMAT_RGBA8)
		for ty in range(3):
			for tx in range(3):
				composite.blit_rect(src, Rect2i(0, 0, w, h), Vector2i(tx * w, ty * h))
		composite.save_png("res://scratch_tile_check_%s.png" % texture_name)
		print("Wrote scratch_tile_check_%s.png (%dx%d)" % [texture_name, w * 3, h * 3])
	quit()
```

Run it:

```bash
~/.local/bin/godot --headless --path . -s scratch_tile_check.gd
```

Then **read both output images**
(`scratch_tile_check_wet_floor_material.png`,
`scratch_tile_check_water_overlay_material.png`) and visually inspect the
3×3 grid for a repeating seam on either axis. `water_overlay_material.png`
is non-square (222×215) — check both axes independently.

- If either shows a visible seam: stop, do not proceed to Step 4. Report
  back which texture and axis — that's a regen request against the
  SpriteCook asset, not something to patch around in code.
- If both look clean: continue.

- [ ] **Step 4: Delete scratch files**

```bash
rm scratch_tile_check.gd scratch_tile_check_wet_floor_material.png scratch_tile_check_water_overlay_material.png
git status --short
```

Expected: none of the three scratch files appear in `git status` output.

- [ ] **Step 5: Update the asset manifest**

In `spritecook-assets.json`, replace the `water-material` entry (the one
with `"local": "assets/textures/water_material.png"`) with two new
entries. Compute each file's `sha12` first:

```bash
sha256sum assets/textures/wet_floor_material.png | cut -c1-12
sha256sum assets/textures/water_overlay_material.png | cut -c1-12
```

Replace the old entry with (substituting the two computed `sha12` values):

```json
    {
      "asset_id": "167258df-a3ef-4e7a-b9bc-b391a113825c",
      "label": "wet-floor-material",
      "role": "texture",
      "sha12": "<computed>",
      "local": "assets/textures/wet_floor_material.png",
      "notes": "generate_game_art-style seamless texture, murky reddish-brown clay floodwater with subtle even ripples and a dull liquid sheen. Base layer for flooded tiles (WaterIngress hazard) -- sits under water_overlay_material.png. Replaces the earlier water-material asset (0c476bad, plain blue #2673BF, never wired into code). Verified seamless via headless Godot 3x3 tile composite."
    },
    {
      "asset_id": "2bd08a56-f480-4296-b8f8-5c83af7210b7",
      "label": "water-overlay-material",
      "role": "texture",
      "sha12": "<computed>",
      "local": "assets/textures/water_overlay_material.png",
      "notes": "generate_game_art-style seamless texture, murky greenish-brown floodwater with sharp small-scale specular highlights forming a shimmering caustic pattern. Animated overlay drawn on top of wet_floor_material.png via water_overlay.gdshader (TIME-scrolled UV). Verified seamless via headless Godot 3x3 tile composite."
    }
```

- [ ] **Step 6: Commit**

```bash
git add assets/textures/wet_floor_material.png assets/textures/wet_floor_material.png.import \
        assets/textures/water_overlay_material.png assets/textures/water_overlay_material.png.import \
        spritecook-assets.json
git add -u assets/textures/water_material.png assets/textures/water_material.png.import
git commit -m "Add wet-floor and water-overlay textures, retire unused water_material.png"
```

---

### Task 2: Animated water-overlay shader, wired through GroundLayer

**Files:**
- Create: `assets/shaders/water_overlay.gdshader`
- Modify: `world/ground_layer.gd`
- Test: `tests/test_ground_layer.gd`

**Interfaces:**
- Consumes: `assets/textures/water_overlay_material.png` (Task 1, only used by the manual shader-compile check below, not by GroundLayer itself).
- Produces: `GroundLayer.water_overlay_material() -> ShaderMaterial` and `GroundLayer.WaterOverlayShader` (the preloaded shader constant, mirroring the existing `GroundDimShader` constant) — Task 3 assigns this material to the overlay child of the water marker. `GroundLayer.set_dimmed(dimmed: bool)`'s existing signature is unchanged, but now also updates the new material.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_ground_layer.gd`:

```gdscript
func test_ready_creates_the_water_overlay_material() -> void:
	var layer := _make_ground_layer()

	var mat := layer.water_overlay_material()
	assert_not_null(mat)
	assert_eq(mat.shader, GroundLayer.WaterOverlayShader)


func test_set_dimmed_true_sets_the_shader_parameter_on_the_water_overlay_material() -> void:
	var layer := _make_ground_layer()

	layer.set_dimmed(true)

	assert_true(layer.water_overlay_material().get_shader_parameter("dim_enabled"))


func test_set_dimmed_false_clears_the_shader_parameter_on_the_water_overlay_material() -> void:
	var layer := _make_ground_layer()
	layer.set_dimmed(true)

	layer.set_dimmed(false)

	assert_false(layer.water_overlay_material().get_shader_parameter("dim_enabled"))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_ground_layer.gd -gexit
```

Expected: FAIL — `water_overlay_material()` does not exist on `GroundLayer` (parse/script error), and `GroundLayer.WaterOverlayShader` is undefined.

- [ ] **Step 3: Create the shader**

Write `assets/shaders/water_overlay.gdshader`:

```glsl
shader_type canvas_item;

// Same desaturate/darken pass as ground_dim.gdshader, duplicated rather
// than shared: this material also carries a TIME-driven UV scroll
// uniform, which the single shared dim_material() instance every other
// ground-resident node uses can't carry without scrolling every other
// ground texture too (see GroundLayer's own doc comment on why one shared
// instance is otherwise the rule here).
uniform float saturation : hint_range(0.0, 1.0) = 0.6;
uniform float brightness : hint_range(0.0, 1.0) = 0.75;
uniform bool dim_enabled = false;
uniform vec2 scroll_speed = vec2(0.02, 0.015);

void fragment() {
	// No early `return` in fragment() -- this project's renderer rejects it
	// (see ground_dim.gdshader / outline.gdshader). Every branch funnels
	// into one COLOR assignment instead.
	vec2 scrolled_uv = UV + TIME * scroll_speed;
	vec4 base_color = texture(TEXTURE, scrolled_uv) * COLOR;
	if (dim_enabled) {
		float luminance = dot(base_color.rgb, vec3(0.299, 0.587, 0.114));
		vec3 desaturated = mix(vec3(luminance), base_color.rgb, saturation);
		COLOR = vec4(desaturated * brightness, base_color.a);
	} else {
		COLOR = base_color;
	}
}
```

- [ ] **Step 4: Wire it into GroundLayer**

Modify `world/ground_layer.gd`:

```gdscript
const GroundDimShader := preload("res://assets/shaders/ground_dim.gdshader")
const WaterOverlayShader := preload("res://assets/shaders/water_overlay.gdshader")

var _material: ShaderMaterial
var _water_overlay_material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = GroundDimShader
	$FloorRenderer.material = _material

	_water_overlay_material = ShaderMaterial.new()
	_water_overlay_material.shader = WaterOverlayShader


func dim_material() -> ShaderMaterial:
	return _material


## The shared ShaderMaterial for the animated water-tile overlay -- see
## water_overlay.gdshader's own doc comment for why this is a second
## instance instead of reusing dim_material().
func water_overlay_material() -> ShaderMaterial:
	return _water_overlay_material


func set_dimmed(dimmed: bool) -> void:
	_material.set_shader_parameter("dim_enabled", dimmed)
	_water_overlay_material.set_shader_parameter("dim_enabled", dimmed)
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_ground_layer.gd -gexit
```

Expected: PASS, all tests in `test_ground_layer.gd` including the three new ones.

- [ ] **Step 6: Verify the shader actually compiles**

GUT never triggers real shader compilation (see Global Constraints). Write
`scratch_shader_check.gd` at the repo root:

```gdscript
extends Node2D

func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/water_overlay.gdshader")
	var sprite := Sprite2D.new()
	sprite.texture = preload("res://assets/textures/water_overlay_material.png")
	sprite.material = mat
	add_child(sprite)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
```

And `scratch_shader_check.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scratch_shader_check.gd" id="1"]

[node name="ScratchShaderCheck" type="Node2D"]
script = ExtResource("1")
```

Run:

```bash
~/.local/bin/godot --headless --path . res://scratch_shader_check.tscn 2>&1 | grep -i "shader error\|compilation failed"
```

Expected: no output. If anything matches, fix `water_overlay.gdshader` and
re-run before continuing.

Delete the scratch files:

```bash
rm scratch_shader_check.gd scratch_shader_check.gd.uid scratch_shader_check.tscn
git status --short
```

Expected: none of the three appear in `git status`.

- [ ] **Step 7: Commit**

```bash
git add assets/shaders/water_overlay.gdshader world/ground_layer.gd tests/test_ground_layer.gd
git commit -m "Add animated water-overlay shader, sync it through GroundLayer.set_dimmed"
```

---

### Task 3: Two-layer water marker, wired into Level

**Files:**
- Create: `world/water_tile_layer.gd`
- Modify: `world/level.gd:159-161` (remove `WATER_MARKER_COLOR`, add texture/alpha constants), `world/level.gd:662-673` (`_spawn_water_marker`)
- Test: `tests/test_level_hazard_helpers.gd` (replace one test)

**Interfaces:**
- Consumes: `GroundLayer.dim_material()` (existing), `GroundLayer.water_overlay_material()` (Task 2), `res://assets/textures/wet_floor_material.png` and `res://assets/textures/water_overlay_material.png` (Task 1).
- Produces: `class_name WaterTileLayer extends Node2D` with settable properties `texture: Texture2D`, `tile_size: float`, `modulate_color: Color`, `repeat: bool`, drawing that texture filling a `tile_size × tile_size` square centered on the node's own position. `Level._spawn_water_marker(tile: Vector2i) -> Node2D` keeps its existing signature and its existing `_water_nodes[tile]` bookkeeping contract (callers only ever call `queue_free()` on the returned node — unchanged, since it's still one freeable node, now a container with two `WaterTileLayer` children instead of one `Polygon2D`).

- [ ] **Step 1: Write the failing test**

In `tests/test_level_hazard_helpers.gd`, replace
`test_set_water_at_spawns_a_distinct_blue_marker_not_the_pit_marker` with:

```gdscript
func test_set_water_at_spawns_a_distinct_water_marker_not_the_pit_marker() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_water_at(open_cell, true)
	assert_true(level._water_nodes.has(open_cell))
	assert_false(level._pit_nodes.has(open_cell), "water uses its own marker, not the brown pit one")
	var marker: Node2D = level._water_nodes[open_cell]
	assert_eq(marker.get_child_count(), 2, "water marker is a base wet-floor layer plus an animated overlay layer")

	var base: WaterTileLayer = marker.get_child(0)
	assert_eq(base.texture, preload("res://assets/textures/wet_floor_material.png"))
	assert_eq(base.material, level._ground_layer.dim_material())

	var overlay: WaterTileLayer = marker.get_child(1)
	assert_eq(overlay.texture, preload("res://assets/textures/water_overlay_material.png"))
	assert_eq(overlay.material, level._ground_layer.water_overlay_material())
	assert_true(overlay.repeat, "overlay must repeat so its scrolled UV wraps instead of clamping at the texture edge")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_level_hazard_helpers.gd -gexit
```

Expected: FAIL — `WaterTileLayer` is an unknown identifier (parse error), or the old test's `Polygon2D`/`WATER_MARKER_COLOR` references no longer resolve once Step 3 below removes the constant. Both are acceptable red states.

- [ ] **Step 3: Create WaterTileLayer**

Write `world/water_tile_layer.gd`:

```gdscript
class_name WaterTileLayer
extends Node2D
## A single textured square, drawn to exactly fill one maze tile -- used as
## a child layer of Level's water-tile marker (see
## Level._spawn_water_marker()). Two of these stack per flooded tile: a
## static wet-floor base (GroundLayer.dim_material(), repeat=false) and an
## animated water overlay on top (GroundLayer.water_overlay_material(),
## repeat=true so the overlay shader's TIME-scrolled UV sampling wraps
## instead of clamping at the texture edge -- see water_overlay.gdshader).
## draw_texture_rect is the same texture-fill idiom FloorRenderer/
## MazeRenderer already use (9205bbc); a plain Node2D + draw_texture_rect
## sidesteps Polygon2D's own UV-mapping rules entirely, which aren't
## needed here since this always draws exactly one texture onto exactly
## one tile-sized rect.

var texture: Texture2D
var tile_size: float
var modulate_color := Color(1, 1, 1, 1)
var repeat := false


func _draw() -> void:
	var half := tile_size * 0.5
	draw_texture_rect(texture, Rect2(-half, -half, tile_size, tile_size), repeat, modulate_color)
```

- [ ] **Step 4: Wire it into Level**

Modify `world/level.gd`. Replace the constant at line 161:

```gdscript
const WATER_MARKER_COLOR := Color(0.15, 0.45, 0.75, 0.75)
```

with:

```gdscript
var _wet_floor_texture: Texture2D = preload("res://assets/textures/wet_floor_material.png")
var _water_overlay_texture: Texture2D = preload("res://assets/textures/water_overlay_material.png")
const WATER_OVERLAY_ALPHA := 0.7
```

Replace `_spawn_water_marker` (currently lines 662-673):

```gdscript
func _spawn_water_marker(tile: Vector2i) -> Node2D:
	var half := TILE_SIZE * 0.5
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])
	poly.color = WATER_MARKER_COLOR
	poly.position = _tile_centre(tile.x, tile.y)
	_ground_layer.add_child(poly)
	poly.material = _ground_layer.dim_material()
	return poly
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

- [ ] **Step 5: Run the test to verify it passes**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gtest=test_level_hazard_helpers.gd -gexit
```

Expected: PASS, all tests in `tests/test_level_hazard_helpers.gd`.

- [ ] **Step 6: Commit**

```bash
git add world/water_tile_layer.gd world/water_tile_layer.gd.uid world/level.gd tests/test_level_hazard_helpers.gd
git commit -m "Texture flooded tiles: wet-floor base + animated water overlay"
```

---

### Task 4: Full validation and visual confirmation

**Files:** none created or modified — this task only runs checks and, if it finds a problem, sends work back to the relevant earlier task.

**Interfaces:**
- Consumes: everything from Tasks 1-3.

- [ ] **Step 1: Full GUT suite**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
```

Expected: same pass count as a clean checkout plus the 4 new tests (3 in
`test_ground_layer.gd`, 1 replaced in `test_level_hazard_helpers.gd`), i.e.
no new failures. `test_larva_hazards.gd` may still flake (pre-existing,
unrelated — reproduce against an unmodified checkout before treating it as
caused by this work).

- [ ] **Step 2: Import + boot smoke test**

```bash
~/.local/bin/godot --headless --path . --import
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"
```

Expected: no new errors/warnings beyond whatever a clean checkout already
prints (compare against `main` if anything looks suspicious).

- [ ] **Step 3: Manual visual check — trigger a flood and screenshot**

Write a throwaway autoload-free scratch scene that boots `world.tscn`,
waits a couple seconds, force-triggers a `WaterIngress` flood on the
running level, waits ~1-2 more seconds for the overlay's scroll to be
visibly in motion, and captures a screenshot — following this project's
established "temporary autoload, removed after use" pattern from `9205bbc`
(see that commit's message for the exact technique). Confirm visually:

- The flooded tile shows the reddish-brown wet-floor texture as its base.
- The greenish, highlight-flecked overlay is visible on top, not fully
  opaque (the base should still read through).
- Waiting a couple more seconds and taking a second screenshot shows the
  overlay's highlights have visibly drifted compared to the first
  screenshot (confirms the shader's TIME-based scroll is actually running,
  not just compiling).

Remove every scratch file/autoload registration this step added before
moving on — none of it should appear in `git status`.

- [ ] **Step 4: Final `git status` check**

```bash
git status --short
```

Expected: clean (or only intentional, already-committed changes) — no
leftover scratch scripts, scenes, or screenshots.
