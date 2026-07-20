# Centipede Art Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Task 1 is an exception — see its own note below: it must be executed by the controller directly, never dispatched to a subagent, because it requires a live human approval step no subagent can wait on.**

**Goal:** Replace `CentipedeSegment`'s flat placeholder rect with real art (head/tail/straight-body/corner-body pieces, oriented via in-engine rotation) plus a per-centipede random earthy tint, for both `Centipede` and `CentipedeExpressRider`.

**Architecture:** Four SpriteCook-generated pieces live under `assets/sprites/centipede/`. `CentipedeSegment` gains a `Sprite2D` child, a `set_visual(texture, rotation_deg, tint)` setter, and three static pure functions: `orientation_for(index, tiles)` (role + rotation from tile-array neighbors), `texture_for_role(role)`, and `random_body_color()`. `Centipede._sync_segments()` and `CentipedeExpressRider._sync_segments()` (both already called every time the body moves) call through these on top of their existing position update — no new event/tracking needed.

**Tech Stack:** Godot 4.7 (GDScript), GUT test framework, SpriteCook MCP (`generate_game_art`, pixel mode).

## Global Constraints

- Godot binary: `~/.local/bin/godot`. All headless commands run from the repo root (`/home/e3h1x/workspace/burrow/.claude/worktrees/art-pipeline-design`).
- New `.gd` files leave a `.gd.uid` sidecar; new binary assets leave a `.png.import` sidecar. Both must be committed — check `git status` after any asset/script-adding step.
- **This is a hard process requirement, not a suggestion:** after Task 1 generates art, the user must see it and explicitly approve it before Task 2 (or any wiring) begins. Do not auto-flow from generation into wiring, even if this plan is being executed by an otherwise-autonomous subagent-driven-development pass.
- Movement is grid-based and cardinal-only (one tile per step, never diagonal) — confirmed via `Centipede`'s `push_front`/`pop_back` crawl and `CentipedeExpressRider`'s `_turn_clockwise`/`_turn_counter_clockwise`. `orientation_for()`'s direction math assumes every adjacent pair in a tiles array differs by exactly one cardinal step; this assumption is safe given the rest of the codebase's existing movement model.
- `CentipedeSegment`'s collision shape (`RectangleShape2D`, 40×40, `centipede_segment.tscn`) does not change in this plan — visual-only work, per the design's own non-goals.
- This project's established test convention for renderer/visual code: pure logic gets direct unit tests (no scene tree); a setter like `set_visual()` gets a test confirming it actually assigns state, not a pixel assertion.

---

### Task 1: Generate and import the 4 Centipede sprite pieces

**⚠️ Controller-executed only — do not dispatch this task to a subagent.** SpriteCook generation is iterative (the project's own history shows textures needing 1-3 regenerations based on visual feedback), and the user has explicitly asked to see and approve generated art before it's wired into gameplay — a subagent has no way to pause mid-task and wait for a live human response. The controller runs this task directly, in conversation with the user.

**Files:**
- Create: `assets/sprites/centipede/centipede_head.png`
- Create: `assets/sprites/centipede/centipede_tail.png`
- Create: `assets/sprites/centipede/centipede_body_straight.png`
- Create: `assets/sprites/centipede/centipede_body_corner.png`
- Modify: `spritecook-assets.json`

**Interfaces:**
- Produces: the four texture files at the paths above, each with a transparent background and a fairly neutral/desaturated base tone (see design doc §3 for why — `Sprite2D.modulate` multiply-tinting needs a neutral source to reproduce a wide hue range cleanly). Each piece must follow a specific authoring-orientation convention Task 2's rotation math depends on:
  - **Head** and **tail**: pointing "up" (toward the top of the canvas) by default.
  - **Straight body**: running vertically (connects the top edge to the bottom edge).
  - **Corner body**: connects the top edge to the right edge (a single bend shape — this one piece gets rotated to all 4 turn orientations in code, not authored 4 times).

- [ ] **Step 1: Generate each piece via SpriteCook `generate_game_art`**

Use `mode="assets"`, `bg_mode="transparent"`, pixel art style, prompts built from the design spec's style direction (`docs/superpowers/specs/2026-07-20-centipede-art-design.md` §3: blocky/cube-ish pixel art matching the faux-3D wall aesthetic, imposing bulk not menace, neutral/desaturated base tone, ~64px canvas). Use `style_asset_ids`/`reference_asset_id` across the four generations so they read as one consistent set. Iterate on any piece that doesn't match the brief (the project's own history — `wall_material.png` needing 3 attempts, `floor_material.png` needing 1 regeneration — is the expected norm here, not a failure signal).

- [ ] **Step 2: Show the user each generated piece and get explicit approval**

Send the generated images to the user (do not just describe them). Wait for their confirmation that each piece matches their idea before continuing. If they ask for changes, regenerate and re-show — repeat until approved. **Do not proceed to Step 3 without this approval.**

- [ ] **Step 3: Download, import, and verify**

Download the approved assets to the paths listed above. Run:

```bash
~/.local/bin/godot --headless --path . --import
git status --short assets/sprites/centipede/
```

Expected: all 4 `.png` files plus their `.png.import` sidecars appear as new/untracked.

- [ ] **Step 4: Update the asset manifest**

Add 4 entries to `spritecook-assets.json` following the existing format (see `wall-material-v3`/`floor-material-v3-simple` entries for the pattern: `asset_id`, `label`, `role: "sprite"`, `sha12` computed via `sha256sum <file> | cut -c1-12`, `local`, `notes` describing the generation prompt/mode and this project's own reasoning for the authoring-orientation convention).

- [ ] **Step 5: Commit**

```bash
git add assets/sprites/centipede/ spritecook-assets.json
git commit -m "Add Centipede head/tail/body sprite pieces"
```

---

### Task 2: `CentipedeSegment` — Sprite2D, orientation, color

**Files:**
- Modify: `entities/centipede/centipede_segment.gd` (full rewrite)
- Modify: `entities/centipede/centipede_segment.tscn` (add `Sprite2D` child)
- Test: `tests/test_centipede_segment.gd`

**Interfaces:**
- Consumes: the 4 textures from Task 1 (`assets/sprites/centipede/*.png`).
- Produces: `enum CentipedeSegment.Role { HEAD, TAIL, STRAIGHT, CORNER }`; `static func CentipedeSegment.orientation_for(index: int, tiles: Array[Vector2i]) -> Dictionary` (keys `"role": Role`, `"rotation_deg": float`); `static func CentipedeSegment.texture_for_role(role: Role) -> Texture2D`; `static func CentipedeSegment.random_body_color() -> Color`; `func CentipedeSegment.set_visual(texture: Texture2D, rotation_deg: float, tint: Color) -> void`. `take_hit()`'s existing signature/behavior is unchanged. Task 3 and Task 4 both call `orientation_for()`, `texture_for_role()`, `random_body_color()`, and `set_visual()` — exact names/signatures above.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_centipede_segment.gd` (keep the existing `FakeCentipedeBody`/`_make_segment` helpers and existing tests):

```gdscript
func test_orientation_for_single_segment_body_renders_as_head() -> void:
	var tiles: Array[Vector2i] = [Vector2i(5, 5)]
	var o := CentipedeSegment.orientation_for(0, tiles)
	assert_eq(o.role, CentipedeSegment.Role.HEAD)


func test_orientation_for_head_facing_up() -> void:
	var tiles: Array[Vector2i] = [Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7)]
	var o := CentipedeSegment.orientation_for(0, tiles)
	assert_eq(o.role, CentipedeSegment.Role.HEAD)
	assert_eq(o.rotation_deg, 0.0)


func test_orientation_for_head_facing_right() -> void:
	var tiles: Array[Vector2i] = [Vector2i(6, 5), Vector2i(5, 5), Vector2i(4, 5)]
	var o := CentipedeSegment.orientation_for(0, tiles)
	assert_eq(o.role, CentipedeSegment.Role.HEAD)
	assert_eq(o.rotation_deg, 90.0)


func test_orientation_for_tail_facing_down() -> void:
	var tiles: Array[Vector2i] = [Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7)]
	var o := CentipedeSegment.orientation_for(2, tiles)
	assert_eq(o.role, CentipedeSegment.Role.TAIL)
	assert_eq(o.rotation_deg, 180.0)


func test_orientation_for_straight_vertical_body() -> void:
	var tiles: Array[Vector2i] = [Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6)]
	var o := CentipedeSegment.orientation_for(1, tiles)
	assert_eq(o.role, CentipedeSegment.Role.STRAIGHT)
	assert_eq(o.rotation_deg, 0.0)


func test_orientation_for_straight_horizontal_body() -> void:
	var tiles: Array[Vector2i] = [Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5)]
	var o := CentipedeSegment.orientation_for(1, tiles)
	assert_eq(o.role, CentipedeSegment.Role.STRAIGHT)
	assert_eq(o.rotation_deg, 90.0)


func test_orientation_for_corner_connecting_up_and_right() -> void:
	var tiles: Array[Vector2i] = [Vector2i(5, 4), Vector2i(5, 5), Vector2i(6, 5)]
	var o := CentipedeSegment.orientation_for(1, tiles)
	assert_eq(o.role, CentipedeSegment.Role.CORNER)
	assert_eq(o.rotation_deg, 0.0)


func test_orientation_for_corner_connecting_right_and_down() -> void:
	var tiles: Array[Vector2i] = [Vector2i(6, 5), Vector2i(5, 5), Vector2i(5, 6)]
	var o := CentipedeSegment.orientation_for(1, tiles)
	assert_eq(o.role, CentipedeSegment.Role.CORNER)
	assert_eq(o.rotation_deg, 90.0)


func test_texture_for_role_returns_the_matching_texture() -> void:
	assert_eq(CentipedeSegment.texture_for_role(CentipedeSegment.Role.HEAD), CentipedeSegment.HeadTexture)
	assert_eq(CentipedeSegment.texture_for_role(CentipedeSegment.Role.TAIL), CentipedeSegment.TailTexture)
	assert_eq(CentipedeSegment.texture_for_role(CentipedeSegment.Role.STRAIGHT), CentipedeSegment.StraightBodyTexture)
	assert_eq(CentipedeSegment.texture_for_role(CentipedeSegment.Role.CORNER), CentipedeSegment.CornerBodyTexture)


func test_random_body_color_stays_within_declared_hsv_bounds() -> void:
	for i in 50:
		var color := CentipedeSegment.random_body_color()
		assert_true(color.h >= CentipedeSegment.HUE_MIN - 0.001 and color.h <= CentipedeSegment.HUE_MAX + 0.001)
		assert_true(color.s >= CentipedeSegment.SATURATION_MIN - 0.01 and color.s <= CentipedeSegment.SATURATION_MAX + 0.01)
		assert_true(color.v >= CentipedeSegment.VALUE_MIN - 0.01 and color.v <= CentipedeSegment.VALUE_MAX + 0.01)


func test_set_visual_assigns_the_sprites_texture_rotation_and_tint() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)
	var tex := CentipedeSegment.HeadTexture

	segment.set_visual(tex, 90.0, Color(0.5, 0.3, 0.2))

	var sprite := segment.get_node("Sprite2D") as Sprite2D
	assert_eq(sprite.texture, tex)
	assert_eq(sprite.rotation_degrees, 90.0)
	assert_eq(sprite.modulate, Color(0.5, 0.3, 0.2))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_segment.gd -gexit
```

Expected: FAIL — none of `orientation_for`, `texture_for_role`, `random_body_color`, `set_visual`, `Role`, or the texture constants exist yet.

- [ ] **Step 3: Add a `Sprite2D` child to the scene**

In `entities/centipede/centipede_segment.tscn`, add a `Sprite2D` node named `Sprite2D`, parented to the root `CentipedeSegment`, no texture assigned (set at runtime via `set_visual()`).

- [ ] **Step 4: Replace `centipede_segment.gd`**

Replace the entire file:

```gdscript
class_name CentipedeSegment
extends StaticBody2D
## One tile-sized block of a Centipede's body (Centipede entity, sub-project
## H): purely physical/visual, holds no state of its own beyond its current
## sprite/orientation. `take_hit()` forwards straight to the parent
## Centipede so every segment contributes to the same shared hit counter --
## hitting any part of the body counts.
##
## Real art (design: docs/superpowers/specs/2026-07-20-centipede-art-
## design.md) replaces the old flat placeholder rect. orientation_for()
## computes which piece + rotation a segment needs purely from its
## neighbors in a Centipede's own _tiles array (head/tail point "up" by
## authoring convention; straight body runs vertically; corner body
## connects its top edge to its right edge, rotated to the other 3 turn
## shapes in code) -- a pure function so it's directly unit-testable and so
## Centipede._sync_segments() and CentipedeExpressRider._sync_segments()
## (two separate call sites, no shared base class) can't drift out of sync
## with each other.

enum Role { HEAD, TAIL, STRAIGHT, CORNER }

const HeadTexture: Texture2D = preload("res://assets/sprites/centipede/centipede_head.png")
const TailTexture: Texture2D = preload("res://assets/sprites/centipede/centipede_tail.png")
const StraightBodyTexture: Texture2D = preload("res://assets/sprites/centipede/centipede_body_straight.png")
const CornerBodyTexture: Texture2D = preload("res://assets/sprites/centipede/centipede_body_corner.png")

## Target on-screen footprint in pixels -- "fill the tile more fully" than
## the old 40x40 placeholder, computed against whatever the source
## texture's own resolution actually is (not hardcoded to one canvas size),
## so a future re-generation at a different resolution doesn't need a code
## change here.
const VISUAL_FOOTPRINT_PX := 46.0

## Wide earthy hue range (brown/umber through olive-green), muted
## saturation/value -- see design doc §5 for the full reasoning. First-pass
## numbers, easy to retune during playtest.
const HUE_MIN := 0.05
const HUE_MAX := 0.40
const SATURATION_MIN := 0.35
const SATURATION_MAX := 0.6
const VALUE_MIN := 0.35
const VALUE_MAX := 0.55

const _DIRECTION_ROTATIONS := {
	Vector2i.UP: 0.0,
	Vector2i.RIGHT: 90.0,
	Vector2i.DOWN: 180.0,
	Vector2i.LEFT: 270.0,
}

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("centipede_segments")
	# Always renders at its own literal authored color, never relit by the
	# player's VisionLight (playtest finding, same root cause and fix as
	# Blockade.gd's own).
	material = CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


## Assigns this segment's sprite/orientation/tint. Scales the sprite so its
## on-screen footprint is VISUAL_FOOTPRINT_PX regardless of the source
## texture's own resolution.
func set_visual(texture: Texture2D, rotation_deg: float, tint: Color) -> void:
	_sprite.texture = texture
	_sprite.rotation_degrees = rotation_deg
	_sprite.modulate = tint
	var tex_size := texture.get_size()
	if tex_size.x > 0.0:
		_sprite.scale = Vector2.ONE * (VISUAL_FOOTPRINT_PX / tex_size.x)


static func texture_for_role(role: Role) -> Texture2D:
	match role:
		Role.HEAD:
			return HeadTexture
		Role.TAIL:
			return TailTexture
		Role.CORNER:
			return CornerBodyTexture
		_:
			return StraightBodyTexture


## Which piece + rotation a segment at `index` within `tiles` (head-first,
## Centipede._tiles' own contract) needs, purely from its neighbors. Pure
## function so it's directly unit-testable without a scene tree, matching
## this codebase's established pattern for this kind of logic (e.g.
## MazeRenderer.wall_occludes_extent()).
static func orientation_for(index: int, tiles: Array[Vector2i]) -> Dictionary:
	if tiles.size() == 1:
		# Both head and tail at once -- extremely unlikely given
		# Level.CENTIPEDE_BODY_LENGTH_MIN=3, but never leave this branch to
		# an out-of-bounds neighbor lookup below if body_length is ever
		# configured down to 1.
		return {"role": Role.HEAD, "rotation_deg": 0.0}
	if index == 0:
		return {"role": Role.HEAD, "rotation_deg": _DIRECTION_ROTATIONS[tiles[0] - tiles[1]]}
	if index == tiles.size() - 1:
		return {"role": Role.TAIL, "rotation_deg": _DIRECTION_ROTATIONS[tiles[index] - tiles[index - 1]]}
	var to_head: Vector2i = tiles[index - 1] - tiles[index]
	var to_tail: Vector2i = tiles[index + 1] - tiles[index]
	if to_head == -to_tail:
		var vertical := to_head == Vector2i.UP or to_head == Vector2i.DOWN
		return {"role": Role.STRAIGHT, "rotation_deg": 0.0 if vertical else 90.0}
	return {"role": Role.CORNER, "rotation_deg": _corner_rotation_for(to_head, to_tail)}


## The canonical corner piece connects UP+RIGHT at rotation 0 (authoring
## convention, see this file's own class doc comment) -- the other 3 turn
## shapes are that same piece rotated 90 degrees at a time, clockwise:
## UP+RIGHT -> RIGHT+DOWN -> DOWN+LEFT -> LEFT+UP.
static func _corner_rotation_for(dir_a: Vector2i, dir_b: Vector2i) -> float:
	var pair := {dir_a: true, dir_b: true}
	if pair.has(Vector2i.UP) and pair.has(Vector2i.RIGHT):
		return 0.0
	if pair.has(Vector2i.RIGHT) and pair.has(Vector2i.DOWN):
		return 90.0
	if pair.has(Vector2i.DOWN) and pair.has(Vector2i.LEFT):
		return 180.0
	return 270.0


static func random_body_color() -> Color:
	return Color.from_hsv(
		randf_range(HUE_MIN, HUE_MAX),
		randf_range(SATURATION_MIN, SATURATION_MAX),
		randf_range(VALUE_MIN, VALUE_MAX)
	)


## Forwards to the owning Centipede's shared counter -- called by WebShot
## (physics overlap) and, via Centipede.hit_segment_at(), by Player/Enemy's
## melee too; the segment itself never tracks a hit count. `hit_direction`
## gives this segment the same nudge-and-slide-back bump Blockade.take_hit()
## uses (CombatFx.shunt) -- a hit visibly registers on the exact segment
## struck even though intact segments don't otherwise react.
func take_hit(hit_direction: Vector2 = Vector2.ZERO) -> void:
	CombatFx.shunt(self, hit_direction * 5.0)
	var parent := get_parent()
	if parent != null and parent.has_method("take_hit"):
		parent.take_hit()
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_segment.gd -gexit
```

Expected: PASS, all tests including the pre-existing `take_hit`/group-membership ones.

- [ ] **Step 6: Commit**

```bash
git add entities/centipede/centipede_segment.gd entities/centipede/centipede_segment.tscn tests/test_centipede_segment.gd
git commit -m "CentipedeSegment: real art via Sprite2D, orientation, and per-body tint"
```

---

### Task 3: Wire into `Centipede`

**Files:**
- Modify: `entities/centipede/centipede.gd:19-30` (add `_body_color`), `:56-67` (`spawn_at`), `:426-430` (`_sync_segments`)
- Test: `tests/test_centipede.gd` (already has the `_make_level()`/`_make_centipede(level, tiles)` helpers this test needs — use them, don't reinvent)

**Interfaces:**
- Consumes: `CentipedeSegment.random_body_color()`, `CentipedeSegment.orientation_for()`, `CentipedeSegment.texture_for_role()`, `CentipedeSegment.set_visual()` (Task 2).
- Produces: no change to `Centipede.spawn_at(tiles: Array[Vector2i]) -> void`'s signature; `_sync_segments()` keeps its existing `() -> void` signature and existing callers unaffected — it now additionally updates each segment's visual, not just its position.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_centipede.gd`, alongside its existing `test_spawn_at_*` tests:

```gdscript
func test_spawn_at_gives_every_segment_a_real_texture_and_a_shared_body_color() -> void:
	var level := _make_level()
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]
	var centipede := _make_centipede(level, tiles)

	var segments := centipede.get_segments()
	var first_color: Color = segments[0].get_node("Sprite2D").modulate
	for segment in segments:
		var sprite := segment.get_node("Sprite2D") as Sprite2D
		assert_not_null(sprite.texture, "every segment must have a real texture assigned, not a placeholder draw")
		assert_eq(sprite.modulate, first_color, "every segment of one centipede shares the same random body color")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede.gd -gexit
```

Expected: FAIL — segments have no `Sprite2D` texture assigned yet (Task 2's `CentipedeSegment` changes are in place, but `Centipede` doesn't call `set_visual()` yet).

- [ ] **Step 3: Add `_body_color` and wire `_sync_segments()`**

In `entities/centipede/centipede.gd`, add near the other instance vars (after line 30's `_exit_steps_remaining`):

```gdscript
var _body_color: Color
```

Replace `_sync_segments()` (currently lines 426-430):

```gdscript
func _sync_segments() -> void:
	for i in _segments.size():
		if i < _tiles.size():
			_segments[i].global_position = _level.tile_centre(_tiles[i])
```

with:

```gdscript
func _sync_segments() -> void:
	for i in _segments.size():
		if i < _tiles.size():
			_segments[i].global_position = _level.tile_centre(_tiles[i])
			var orientation := CentipedeSegment.orientation_for(i, _tiles)
			_segments[i].set_visual(CentipedeSegment.texture_for_role(orientation.role), orientation.rotation_deg, _body_color)
```

- [ ] **Step 4: Update `spawn_at()` to set the color and delegate to `_sync_segments()`**

Replace `spawn_at()` (currently lines 56-67):

```gdscript
func spawn_at(tiles: Array[Vector2i]) -> void:
	_tiles = tiles.duplicate()
	for segment in _segments:
		if is_instance_valid(segment):
			segment.queue_free()
	_segments.clear()
	for tile in _tiles:
		_level._destroy_occupants_at(tile)
		var segment: CentipedeSegment = SegmentScene.instantiate()
		add_child(segment)
		segment.global_position = _level.tile_centre(tile)
		_segments.append(segment)
```

with:

```gdscript
func spawn_at(tiles: Array[Vector2i]) -> void:
	_tiles = tiles.duplicate()
	for segment in _segments:
		if is_instance_valid(segment):
			segment.queue_free()
	_segments.clear()
	for tile in _tiles:
		_level._destroy_occupants_at(tile)
		var segment: CentipedeSegment = SegmentScene.instantiate()
		add_child(segment)
		_segments.append(segment)
	_body_color = CentipedeSegment.random_body_color()
	_sync_segments()
```

(`segment.global_position` is no longer set directly here — `_sync_segments()`, called at the end, now handles position AND visual together, so there's exactly one place that does it instead of two.)

- [ ] **Step 5: Run the test to verify it passes**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede.gd -gexit
```

Expected: PASS.

- [ ] **Step 6: Run the full Centipede test suite to confirm no regression**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_crawl.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_reverse.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_flee.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_relocate.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_pathing.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_tunnel_fallback.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_level_centipede_seeding.gd -gexit
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_enemy_centipede_melee.gd -gexit
```

Expected: PASS on all, same as each file's own pre-change baseline.

- [ ] **Step 7: Commit**

```bash
git add entities/centipede/centipede.gd tests/
git commit -m "Centipede: wire real art (orientation + per-body random color) into spawn/sync"
```

---

### Task 4: Wire into `CentipedeExpressRider`

**Files:**
- Modify: `entities/centipede/centipede_express_rider.gd:27-41` (add `_body_color`), `:62-77` (`start_run`), `:162-165` (`_sync_segments`)
- Test: `tests/test_centipede_express_rider.gd`

**Interfaces:**
- Consumes: same `CentipedeSegment` statics as Task 3.
- Produces: no change to `start_run(entry: Vector2i, direction: Vector2i) -> void`'s signature; `_sync_segments()` keeps its existing signature.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_centipede_express_rider.gd`, using its existing `_make_level()`/`_make_rider(level, entry, direction)` helpers:

```gdscript
func test_start_run_gives_every_segment_a_real_texture_and_a_shared_body_color() -> void:
	var level := _make_level()
	var rider := _make_rider(level, Vector2i(5, 5), Vector2i.RIGHT)

	var segments := rider.get_segments()
	assert_true(segments.size() > 0)
	var first_color: Color = segments[0].get_node("Sprite2D").modulate
	for segment in segments:
		var sprite := segment.get_node("Sprite2D") as Sprite2D
		assert_not_null(sprite.texture, "every segment must have a real texture assigned")
		assert_eq(sprite.modulate, first_color, "every segment shares the same random body color")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_express_rider.gd -gexit
```

Expected: FAIL — segments have no texture assigned yet.

- [ ] **Step 3: Add `_body_color` and wire `_sync_segments()`**

In `entities/centipede/centipede_express_rider.gd`, add near the other instance vars (after line 41's `_exit_steps_remaining`):

```gdscript
var _body_color: Color
```

Replace `_sync_segments()` (currently lines 162-165):

```gdscript
func _sync_segments() -> void:
	for i in _segments.size():
		if i < _tiles.size():
			_segments[i].global_position = _level.tile_centre(_tiles[i])
```

with:

```gdscript
func _sync_segments() -> void:
	for i in _segments.size():
		if i < _tiles.size():
			_segments[i].global_position = _level.tile_centre(_tiles[i])
			var orientation := CentipedeSegment.orientation_for(i, _tiles)
			_segments[i].set_visual(CentipedeSegment.texture_for_role(orientation.role), orientation.rotation_deg, _body_color)
```

- [ ] **Step 4: Update `start_run()` to set the color and delegate to `_sync_segments()`**

Replace `start_run()` (currently lines 62-77):

```gdscript
func start_run(entry: Vector2i, direction: Vector2i) -> void:
	_direction = direction
	_exiting = false
	_tiles.clear()
	for i in body_length:
		_tiles.append(entry - direction * (i + 1))
	for segment in _segments:
		if is_instance_valid(segment):
			segment.queue_free()
	_segments.clear()
	for tile in _tiles:
		var segment: CentipedeSegment = SegmentScene.instantiate()
		add_child(segment)
		segment.global_position = _level.tile_centre(tile)
		_segments.append(segment)
	_schedule_next_step()
```

with:

```gdscript
func start_run(entry: Vector2i, direction: Vector2i) -> void:
	_direction = direction
	_exiting = false
	_tiles.clear()
	for i in body_length:
		_tiles.append(entry - direction * (i + 1))
	for segment in _segments:
		if is_instance_valid(segment):
			segment.queue_free()
	_segments.clear()
	for tile in _tiles:
		var segment: CentipedeSegment = SegmentScene.instantiate()
		add_child(segment)
		_segments.append(segment)
	_body_color = CentipedeSegment.random_body_color()
	_sync_segments()
	_schedule_next_step()
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_express_rider.gd -gexit
```

Expected: PASS, all tests in the file.

- [ ] **Step 6: Commit**

```bash
git add entities/centipede/centipede_express_rider.gd tests/test_centipede_express_rider.gd
git commit -m "CentipedeExpressRider: wire real art (orientation + per-body random color)"
```

---

### Task 5: Full validation and visual confirmation

**Files:** none created or modified — this task only runs checks.

**Interfaces:**
- Consumes: everything from Tasks 1-4.

- [ ] **Step 1: Full GUT suite**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
```

Expected: no new failures beyond this project's already-documented pre-existing order/timing flakiness. Any failure in a Centipede-related test file is this plan's own regression — stop and fix before continuing.

- [ ] **Step 2: Import + boot smoke test**

```bash
~/.local/bin/godot --headless --path . --import
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"
```

Expected: no new errors/warnings.

- [ ] **Step 3: Manual visual check**

Boot the game windowed and confirm:
- A centipede's head and tail render as distinct pieces from its body, facing the correct direction as it crawls.
- A body segment at a turn shows the corner piece, rotated to match the actual bend — not a straight piece misaligned with one neighbor.
- Multiple centipedes (or a centipede and an Express rider) on screen at once show visibly different colors from each other, all within the earthy palette (no neon, no colors outside brown/olive/green).
- The body reads as noticeably chunkier/more filling its tile than the old 40×40 placeholder.

If using any temporary script/scene/autoload for this check, remove it afterward — confirm with `git status --short` that nothing scratch remains.

- [ ] **Step 4: Final `git status` check**

```bash
git status --short
```

Expected: clean.
