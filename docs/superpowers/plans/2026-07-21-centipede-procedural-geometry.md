# Centipede Procedural Geometry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `CentipedeSegment`'s flat placeholder rect with a shaded sphere (3 layered `draw_circle()` calls, no sprite art), sized by head/body/tail position, tinted with a per-centipede random earthy color, for both `Centipede` and `CentipedeExpressRider`. **Visual-only** — no change to collision, movement, AI, combat, or `WallOverdrawMask` integration (see design doc §2 for the full non-goals list).

**Architecture:** `CentipedeSegment` gains `_radius`/`_tint` instance vars, a `set_visual(radius, tint)` setter, and two static pure functions: `radius_for_index(index, count)` and `random_body_color()`. `_draw()` is rewritten to draw the sphere instead of the flat rect. `Centipede._sync_segments()` and `CentipedeExpressRider._sync_segments()` (both already called every time the body moves) call through these on top of their existing position update — no new event/tracking, no scene-file changes (no new nodes).

**Tech Stack:** Godot 4.7 (GDScript), GUT test framework.

## Global Constraints

- Godot binary: `~/.local/bin/godot`. All headless commands run from the repo root (`/home/e3h1x/workspace/burrow/.claude/worktrees/art-pipeline-design`).
- New `.gd` files leave a `.gd.uid` sidecar (none expected in this plan — no new files). Check `git status` after each step regardless.
- `CentipedeSegment`'s collision shape (`RectangleShape2D`, 40×40, `centipede_segment.tscn`) does not change — visual-only work.
- `WallOverdrawMask` needs no changes — it occludes purely by `global_position`/`ENTITY_VISUAL_HALF_EXTENT`, with no dependency on how a segment draws itself (confirmed during design).
- This project's established test convention: pure logic gets direct unit tests (no scene tree); a setter like `set_visual()` gets a test confirming it actually assigns state (`_radius`/`_tint` are accessed directly in tests — GDScript's underscore prefix is a style convention, not enforced privacy, and this codebase's existing tests already reach into node state this way, e.g. `segment.position` in `test_centipede_segment.gd`).

---

### Task 1: `CentipedeSegment` — sphere geometry, radius-by-index, color

**Files:**
- Modify: `entities/centipede/centipede_segment.gd` (full rewrite)
- Test: `tests/test_centipede_segment.gd`

**Interfaces:**
- Produces: `const CentipedeSegment.HEAD_RADIUS/BODY_RADIUS/TAIL_RADIUS: float`; `static func CentipedeSegment.radius_for_index(index: int, count: int) -> float`; `static func CentipedeSegment.random_body_color() -> Color`; `func CentipedeSegment.set_visual(radius: float, tint: Color) -> void`. `take_hit()`'s existing signature/behavior is unchanged. Task 2 and Task 3 both call `radius_for_index()`, `random_body_color()`, and `set_visual()` — exact names/signatures above.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_centipede_segment.gd` (keep the existing `FakeCentipedeBody`/`_make_segment` helpers and existing tests):

```gdscript
func test_radius_for_index_head_is_index_zero() -> void:
	assert_eq(CentipedeSegment.radius_for_index(0, 5), CentipedeSegment.HEAD_RADIUS)


func test_radius_for_index_tail_is_the_last_index() -> void:
	assert_eq(CentipedeSegment.radius_for_index(4, 5), CentipedeSegment.TAIL_RADIUS)


func test_radius_for_index_body_is_any_middle_index() -> void:
	assert_eq(CentipedeSegment.radius_for_index(1, 5), CentipedeSegment.BODY_RADIUS)
	assert_eq(CentipedeSegment.radius_for_index(2, 5), CentipedeSegment.BODY_RADIUS)
	assert_eq(CentipedeSegment.radius_for_index(3, 5), CentipedeSegment.BODY_RADIUS)


func test_radius_for_index_single_segment_body_counts_as_head() -> void:
	assert_eq(CentipedeSegment.radius_for_index(0, 1), CentipedeSegment.HEAD_RADIUS)


func test_random_body_color_stays_within_declared_hsv_bounds() -> void:
	for i in 50:
		var color := CentipedeSegment.random_body_color()
		assert_true(color.h >= CentipedeSegment.HUE_MIN - 0.001 and color.h <= CentipedeSegment.HUE_MAX + 0.001)
		assert_true(color.s >= CentipedeSegment.SATURATION_MIN - 0.01 and color.s <= CentipedeSegment.SATURATION_MAX + 0.01)
		assert_true(color.v >= CentipedeSegment.VALUE_MIN - 0.01 and color.v <= CentipedeSegment.VALUE_MAX + 0.01)


func test_set_visual_assigns_radius_and_tint() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)

	segment.set_visual(30.0, Color(0.5, 0.3, 0.2))

	assert_eq(segment._radius, 30.0)
	assert_eq(segment._tint, Color(0.5, 0.3, 0.2))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_segment.gd -gexit
```

Expected: FAIL — none of `radius_for_index`, `random_body_color`, `set_visual`, or the radius/HSV constants exist yet.

- [ ] **Step 3: Replace `centipede_segment.gd`**

Replace the entire file:

```gdscript
class_name CentipedeSegment
extends StaticBody2D
## One tile-sized block of a Centipede's body (Centipede entity, sub-project
## H): purely physical/visual, holds no state of its own beyond its current
## radius/tint. `take_hit()` forwards straight to the parent Centipede so
## every segment contributes to the same shared hit counter -- hitting any
## part of the body counts.
##
## Visual: a shaded sphere (three layered draw_circle() calls: shadow-
## offset base, main fill, highlight), no sprite art -- pure geometry was a
## deliberate final choice after 3 rounds of AI-generated sprite art didn't
## converge (see docs/superpowers/specs/2026-07-21-centipede-procedural-
## geometry-design.md). radius_for_index() picks HEAD/BODY/TAIL_RADIUS
## purely from a segment's position in Centipede._tiles -- no per-role
## rotation or shape is needed, since a sphere looks identical from every
## angle, unlike the sprite-based design this replaced.

const HEAD_RADIUS := 24.0
const BODY_RADIUS := 22.0
const TAIL_RADIUS := 17.0

## Wide earthy hue range (brown/umber through olive-green), muted
## saturation/value -- see design doc §4 for the full reasoning. First-pass
## numbers, easy to retune during playtest.
const HUE_MIN := 0.05
const HUE_MAX := 0.40
const SATURATION_MIN := 0.35
const SATURATION_MAX := 0.6
const VALUE_MIN := 0.35
const VALUE_MAX := 0.55

var _radius: float = BODY_RADIUS
var _tint: Color = Color(0.3, 0.45, 0.2)


func _ready() -> void:
	add_to_group("centipede_segments")
	# Always renders at its own literal authored color, never relit by the
	# player's VisionLight (playtest finding, same root cause and fix as
	# Blockade.gd's own).
	material = CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


## Assigns this segment's size/color and requests a redraw.
func set_visual(radius: float, tint: Color) -> void:
	_radius = radius
	_tint = tint
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(2, 3), _radius, _tint.darkened(0.4))
	draw_circle(Vector2.ZERO, _radius - 2.0, _tint)
	draw_circle(Vector2(-_radius * 0.22, -_radius * 0.25), _radius * 0.45, _tint.lightened(0.18))


## Which radius a segment at `index` within a body of `count` segments
## needs, purely from its position -- pure function so it's directly
## unit-testable without a scene tree, matching this codebase's established
## pattern for this kind of logic (e.g. MazeRenderer.wall_occludes_extent()).
static func radius_for_index(index: int, count: int) -> float:
	if count <= 1 or index == 0:
		return HEAD_RADIUS
	if index == count - 1:
		return TAIL_RADIUS
	return BODY_RADIUS


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

- [ ] **Step 4: Run the tests to verify they pass**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_segment.gd -gexit
```

Expected: PASS, all tests including the pre-existing `take_hit`/group-membership ones.

- [ ] **Step 5: Commit**

```bash
git add entities/centipede/centipede_segment.gd tests/test_centipede_segment.gd
git commit -m "CentipedeSegment: procedural sphere geometry replaces flat rect placeholder"
```

---

### Task 2: Wire into `Centipede`

**Files:**
- Modify: `entities/centipede/centipede.gd:19-30` (add `_body_color`), `:56-67` (`spawn_at`), `:426-430` (`_sync_segments`)
- Test: `tests/test_centipede.gd` (already has the `_make_level()`/`_make_centipede(level, tiles)` helpers this test needs — use them, don't reinvent)

**Interfaces:**
- Consumes: `CentipedeSegment.random_body_color()`, `CentipedeSegment.radius_for_index()`, `CentipedeSegment.set_visual()` (Task 1).
- Produces: no change to `Centipede.spawn_at(tiles: Array[Vector2i]) -> void`'s signature; `_sync_segments()` keeps its existing `() -> void` signature and existing callers unaffected — it now additionally updates each segment's visual, not just its position.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_centipede.gd`, alongside its existing `test_spawn_at_*` tests:

```gdscript
func test_spawn_at_gives_head_and_tail_different_radii_and_a_shared_body_color() -> void:
	var level := _make_level()
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]
	var centipede := _make_centipede(level, tiles)

	var segments := centipede.get_segments()
	var first_color: Color = segments[0]._tint
	assert_eq(segments[0]._radius, CentipedeSegment.HEAD_RADIUS)
	assert_eq(segments[1]._radius, CentipedeSegment.BODY_RADIUS)
	assert_eq(segments[2]._radius, CentipedeSegment.TAIL_RADIUS)
	for segment in segments:
		assert_eq(segment._tint, first_color, "every segment of one centipede shares the same random body color")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede.gd -gexit
```

Expected: FAIL — segments still have the default `BODY_RADIUS`/default tint from Task 1's constructor defaults, not per-index/per-spawn values yet.

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
			_segments[i].set_visual(CentipedeSegment.radius_for_index(i, _tiles.size()), _body_color)
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

Expected: PASS on all, same as each file's own pre-change baseline — none of this logic (movement/AI/combat) was touched.

- [ ] **Step 7: Commit**

```bash
git add entities/centipede/centipede.gd tests/
git commit -m "Centipede: wire per-index radius + per-body random color into spawn/sync"
```

---

### Task 3: Wire into `CentipedeExpressRider`

**Files:**
- Modify: `entities/centipede/centipede_express_rider.gd:27-41` (add `_body_color`), `:62-77` (`start_run`), `:162-165` (`_sync_segments`)
- Test: `tests/test_centipede_express_rider.gd`

**Interfaces:**
- Consumes: same `CentipedeSegment` statics as Task 2.
- Produces: no change to `start_run(entry: Vector2i, direction: Vector2i) -> void`'s signature; `_sync_segments()` keeps its existing signature.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_centipede_express_rider.gd`, using its existing `_make_level()`/`_make_rider(level, entry, direction)` helpers:

```gdscript
func test_start_run_gives_head_and_tail_different_radii_and_a_shared_body_color() -> void:
	var level := _make_level()
	var rider := _make_rider(level, Vector2i(5, 5), Vector2i.RIGHT)

	var segments := rider.get_segments()
	assert_true(segments.size() > 1)
	var first_color: Color = segments[0]._tint
	assert_eq(segments[0]._radius, CentipedeSegment.HEAD_RADIUS)
	assert_eq(segments[segments.size() - 1]._radius, CentipedeSegment.TAIL_RADIUS)
	for segment in segments:
		assert_eq(segment._tint, first_color, "every segment shares the same random body color")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gselect=test_centipede_express_rider.gd -gexit
```

Expected: FAIL — segments still have Task 1's constructor defaults, not per-index/per-spawn values.

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
			_segments[i].set_visual(CentipedeSegment.radius_for_index(i, _tiles.size()), _body_color)
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
git commit -m "CentipedeExpressRider: wire per-index radius + per-body random color"
```

---

### Task 4: Full validation and visual confirmation

**Files:** none created or modified — this task only runs checks and removes scratch files.

- [ ] **Step 1: Full GUT suite**

```bash
~/.local/bin/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
```

Expected: no new failures beyond this project's already-documented pre-existing order/timing flakiness (`test_larva_hazards.gd`). Any failure in a Centipede-related test file is this plan's own regression — stop and fix before continuing.

- [ ] **Step 2: Import + boot smoke test**

```bash
~/.local/bin/godot --headless --path . --import
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"
```

Expected: no new errors/warnings.

- [ ] **Step 3: Manual visual check**

Boot the game windowed (`GALLIUM_DRIVER=d3d12`, see [[wsl-godot-gpu-passthrough]]) and confirm:
- A centipede's head reads bigger than its tail, body segments constant in between.
- A body segment at a turn reads as connected to its neighbors (no gap/misalignment) even though there's no special corner geometry.
- Multiple centipedes (or a centipede and an Express rider) on screen at once show visibly different colors from each other, all within the earthy palette.
- Nothing about movement, AI, or combat behaves differently than before this plan (spot-check: web-shotting a segment still registers a hit and nudges it).

- [ ] **Step 4: Remove scratch mockup files and confirm clean**

```bash
rm -f scratch_centipede_geometry_mockup.gd scratch_centipede_geometry_mockup.tscn scratch_centipede_geometry_mockup.gd.uid
git status --short
```

Expected: clean (these were exploratory design mockups, never committed).
