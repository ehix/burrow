# Centipede Entity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new, multi-tile segmented obstacle creature (`Centipede`) that blocks a corridor on both ground and ceiling planes, reacts to combat (flee to the boundary and despawn) and to flooding (relocate to a fresh dry spot), destroying whatever's on tiles it crawls onto — and retire `Earthworm`, which it replaces.

**Architecture:** `CentipedeSegment` (a `StaticBody2D` leaf, physical/visual only) forwards every hit to its owning `Centipede` (a `Node2D` that owns `_tiles: Array[Vector2i]`, the single source of truth for the body's occupied tiles, shifted snake-style as it crawls). Combat and dual-plane blocking are modeled directly on the existing `Blockade` pattern (a plain hit counter, no `HealthComponent`; checked in `Level.is_blocked()` before the ground/ceiling branch). Movement uses a small Centipede-local BFS (not the shared Enemy/Player AStar) that treats walls and flooded tiles as impassable, with a wall-carving fallback when boxed in, paced by real `SceneTreeTimer`s the way `WaterIngress` paces its rings.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-13-centipede-entity-design.md` — read once for full context.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1` (read the full output, not `tail`; drop `-gselect=` for the whole suite).
- Import check after any `.tscn` edit: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- New `.gd`/`.tscn` files generate an untracked `.gd.uid`/`.tscn.uid` sidecar the first time Godot imports/runs them — after each task, run `git status` and stage any stray sidecar files.
- Any combative strike (melee or web-shot) from either Player or Enemy, landing on **any** segment, counts toward one shared hit counter for the whole body (confirmed explicitly during design).
- A Centipede segment blocks **both** `Level.Layer.GROUND` and `Level.Layer.CEILING` on its tile — this is the one thing that distinguishes it from a natural pit/flood (ground-only) in this codebase.
- Water is never stepped onto during a crawl (flee or relocate) — `Level.is_water_at(tile)` (new in Task 4) is the query every pathing decision must respect, mirroring how `Level.is_water_at`/`_water_tiles` already gate ground movement elsewhere.
- Occupant destruction (`Level._destroy_occupants_at`, already built in sub-project G) happens on every tile the head newly crawls onto, in **both** `FLEEING` and `RELOCATING` — confirmed explicitly during design, this is not limited to relocating alone.
- `Centipede` replaces `Earthworm` entirely — do not build them to coexist as two separate creature types. `Earthworm` is deleted in the final task, after everything that reads its groups/state has a Centipede equivalent to depend on instead.
- Only touch the files each task's **Files** section lists. This plan touches: `entities/centipede/*` (new), `entities/web/web_shot.gd`, `entities/player/player.gd`, `entities/enemy/enemy.gd`, `entities/larva/larva.gd`, `world/level.gd`, `resources/prey_type.gd`, `entities/earthworm/*` (deleted in the final task), and their tests. No other system.

---

### Task 1: `CentipedeSegment` — the physical/visual leaf node

**Files:**
- Create: `entities/centipede/centipede_segment.gd`
- Create: `entities/centipede/centipede_segment.tscn`
- Modify: `entities/web/web_shot.gd`
- Modify: `world/level.gd`
- Test: `tests/test_centipede_segment.gd` (new)
- Test: `tests/test_web_shot.gd` (extend)
- Test: `tests/test_level_sense_and_pits.gd` (extend)

**Interfaces:**
- Produces: `CentipedeSegment.take_hit() -> void` (consumed by Task 2's `Centipede`, and by `WebShot`/Player/Enemy melee in this and later tasks). `CentipedeSegment extends StaticBody2D`, joins group `"centipede_segments"`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_centipede_segment.gd`:

```gdscript
extends GutTest
## CentipedeSegment (Centipede entity, sub-project H): a purely physical/
## visual leaf -- take_hit() forwards to whatever parent it's under, since
## the real Centipede owns the actual shared hit counter (tested here via a
## lightweight double, not the real Centipede, which doesn't exist until a
## later task in this plan).

class FakeCentipedeBody:
	extends Node2D
	var hits := 0
	func take_hit() -> void:
		hits += 1

const SegmentScene := preload("res://entities/centipede/centipede_segment.tscn")


func _make_segment(parent: Node2D) -> CentipedeSegment:
	var segment: CentipedeSegment = SegmentScene.instantiate()
	parent.add_child(segment)
	return segment


func test_joins_the_centipede_segments_group() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)
	assert_true(segment.is_in_group("centipede_segments"))


func test_take_hit_forwards_to_the_parent() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)
	segment.take_hit()
	assert_eq(body.hits, 1)


func test_take_hit_forwards_every_time_not_just_once() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment := _make_segment(body)
	segment.take_hit()
	segment.take_hit()
	segment.take_hit()
	assert_eq(body.hits, 3, "a segment holds no state of its own -- every hit forwards")
```

Append to `tests/test_web_shot.gd` (reusing its existing `_make_shot()` helper exactly):

```gdscript
class FakeCentipedeBody:
	extends Node2D
	var hits := 0
	func take_hit() -> void:
		hits += 1


func test_hitting_a_centipede_segment_registers_a_hit() -> void:
	var body := FakeCentipedeBody.new()
	add_child_autofree(body)
	var segment: CentipedeSegment = preload("res://entities/centipede/centipede_segment.tscn").instantiate()
	body.add_child(segment)
	_make_shot()._on_body_entered(segment)
	assert_eq(body.hits, 1, "a web-shot hitting any segment forwards to the shared counter")
```

Append to `tests/test_level_sense_and_pits.gd` (reusing its existing `_make_level()` helper exactly — mirrors that file's own `test_set_sense_outline_boxes_a_nearby_world_item`):

```gdscript
func test_set_sense_outline_boxes_a_nearby_centipede_segment() -> void:
	var level := _make_level()
	var segment: CentipedeSegment = preload("res://entities/centipede/centipede_segment.tscn").instantiate()
	level.add_child(segment)
	segment.global_position = level.player.global_position

	level.set_sense_outline(true, 50.0)

	assert_true(level._sense_point_highlights.has(segment))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_segment.gd 2>&1`
Expected: FAIL — `Could not find script matching 'test_centipede_segment.gd'` or a resource-not-found error, since `entities/centipede/centipede_segment.tscn` doesn't exist yet.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_web_shot.gd 2>&1`
Expected: FAIL — same resource-not-found error on the new test.

- [ ] **Step 3: Write the implementation**

Create `entities/centipede/centipede_segment.gd`:

```gdscript
class_name CentipedeSegment
extends StaticBody2D
## One tile-sized block of a Centipede's body (Centipede entity, sub-project
## H): purely physical/visual, holds no state of its own. `take_hit()`
## forwards straight to the parent Centipede so every segment contributes to
## the same shared hit counter -- hitting any part of the body counts.
## Placeholder visual: a drawn segment shape, no art asset yet (mirrors
## Earthworm/Blockade's own "no art asset yet" precedent).

func _ready() -> void:
	add_to_group("centipede_segments")


func _draw() -> void:
	var half := Vector2(20.0, 20.0)
	draw_rect(Rect2(-half, half * 2.0), Color(0.3, 0.45, 0.2, 0.9))


## Forwards to the owning Centipede's shared counter -- called by WebShot
## (physics overlap) and by Player/Enemy's melee (exact-tile lookup via
## Centipede.segment_at_tile()) identically; the segment itself never tracks
## a hit count.
func take_hit() -> void:
	var parent := get_parent()
	if parent != null and parent.has_method("take_hit"):
		parent.take_hit()
```

Create `entities/centipede/centipede_segment.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://entities/centipede/centipede_segment.gd" id="1_seg"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_seg"]
size = Vector2(40, 40)

[node name="CentipedeSegment" type="StaticBody2D"]
collision_layer = 1
collision_mask = 0
script = ExtResource("1_seg")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_seg")
```

In `entities/web/web_shot.gd`, modify `_on_body_entered()`:

```gdscript
func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	if body is WebTrap:
		(body as WebTrap).take_web_hit()
	elif body is Blockade:
		(body as Blockade).take_hit(_velocity.normalized())
	elif body is CentipedeSegment:
		(body as CentipedeSegment).take_hit()
	elif body.is_in_group("larvae") and body.has_method("web_kill"):
		body.web_kill()
	# else: a wall — nothing to do but splat.
	_leave_splat()
	_despawn()
```

In `world/level.gd`, modify `SENSE_POINT_HALF_SIZE`:

```gdscript
## Per-group box half-size for the point-entity outline, roughly matching
## each placeholder's own `_draw()` shape.
const SENSE_POINT_HALF_SIZE := {
	"world_items": Vector2(9, 9),
	"earthworms": Vector2(18, 8),
	"centipede_segments": Vector2(20, 20),
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_segment.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_web_shot.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_sense_and_pits.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add entities/centipede/centipede_segment.gd entities/centipede/centipede_segment.tscn entities/web/web_shot.gd world/level.gd tests/test_centipede_segment.gd tests/test_web_shot.gd tests/test_level_sense_and_pits.gd
git status # stage a stray .gd.uid/.tscn.uid if one appears
git commit -m "CentipedeSegment: physical/visual leaf, WebShot + Sense integration"
```

---

### Task 2: `Centipede` — data model, hit counter, dual-plane blocking

**Files:**
- Create: `entities/centipede/centipede.gd`
- Create: `entities/centipede/centipede.tscn`
- Modify: `world/level.gd`
- Test: `tests/test_centipede.gd` (new)

**Interfaces:**
- Consumes: `CentipedeSegment` (Task 1).
- Produces: `Centipede.spawn_at(tiles: Array[Vector2i]) -> void`, `Centipede.take_hit() -> void`, `Centipede.state: State` (enum `BLOCKING/FLEEING/RELOCATING`), `Centipede.bind_level(level: Node) -> void`, `Centipede.segment_at_tile(tree: SceneTree, tile: Vector2i) -> Centipede` (static, consumed by Task 3's melee integration and Task 7's water hook), `Level.tile_centre(tile: Vector2i) -> Vector2` (consumed by this task and by Task 5's segment repositioning).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_centipede.gd`:

```gdscript
extends GutTest
## Centipede (sub-project H): shared hit-counter across the whole body,
## segment_at_tile() lookup, and spawn_at() laying out segment visuals to
## match its tile array. Movement (crawling/fleeing/relocating) is covered
## in later tasks' own test files as it's built.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


func test_spawn_at_creates_one_segment_per_tile() -> void:
	var level := _make_level()
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]
	var centipede := _make_centipede(level, tiles)
	assert_eq(centipede._segments.size(), 3)


func test_spawn_at_positions_each_segment_at_its_tile_centre() -> void:
	var level := _make_level()
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2)]
	var centipede := _make_centipede(level, tiles)
	assert_eq(centipede._segments[0].global_position, level.tile_centre(Vector2i(1, 1)))
	assert_eq(centipede._segments[1].global_position, level.tile_centre(Vector2i(1, 2)))


func test_joins_the_centipedes_group() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1)])
	assert_true(centipede.is_in_group("centipedes"))


func test_take_hit_below_threshold_stays_blocking() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1)])
	centipede.hits_to_flee = 4
	centipede.take_hit()
	centipede.take_hit()
	centipede.take_hit()
	assert_eq(centipede.state, Centipede.State.BLOCKING)


func test_take_hit_at_threshold_begins_fleeing() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1)])
	centipede.hits_to_flee = 4
	for i in 4:
		centipede.take_hit()
	assert_eq(centipede.state, Centipede.State.FLEEING)


func test_take_hit_is_a_noop_once_already_fleeing() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1)])
	centipede.hits_to_flee = 2
	centipede.take_hit()
	centipede.take_hit() # now FLEEING
	centipede.take_hit() # must not error or re-trigger anything odd
	assert_eq(centipede.state, Centipede.State.FLEEING)


func test_segment_at_tile_finds_the_owning_centipede() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1), Vector2i(1, 2)])
	var found := Centipede.segment_at_tile(level.get_tree(), Vector2i(1, 2))
	assert_eq(found, centipede)


func test_segment_at_tile_returns_null_for_an_unoccupied_tile() -> void:
	var level := _make_level()
	_make_centipede(level, [Vector2i(1, 1)])
	var found := Centipede.segment_at_tile(level.get_tree(), Vector2i(5, 5))
	assert_null(found)


func test_level_is_blocked_true_on_a_centipede_tile_for_both_planes() -> void:
	var level := _make_level()
	_make_centipede(level, [Vector2i(3, 3)])
	assert_true(level.is_blocked(Vector2i(3, 3), Level.Layer.GROUND))
	assert_true(level.is_blocked(Vector2i(3, 3), Level.Layer.CEILING))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede.gd 2>&1`
Expected: FAIL — `Could not find type "Centipede"` or similar, since `entities/centipede/centipede.gd` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `entities/centipede/centipede.gd`:

```gdscript
class_name Centipede
extends Node2D
## Multi-tile segmented obstacle creature (Centipede entity, sub-project H,
## replaces Earthworm): stationary and non-combatant while intact, blocking
## a corridor on BOTH ground and ceiling planes at once (see
## Level.is_blocked()) across `body_length` tiles. `_tiles` is the single
## source of truth for which tiles the body currently occupies (head first,
## `_tiles[0]`); CentipedeSegment children are pure visual/physical mirrors
## of it, repositioned whenever `_tiles` changes. Any combative hit --
## melee or web-shot, from Player or Enemy, landing on ANY segment -- adds
## to one shared `_hits` counter (mirrors Blockade's plain counter, not
## HealthComponent: this creature can't be killed, only driven off).

const SegmentScene := preload("res://entities/centipede/centipede_segment.tscn")

enum State { BLOCKING, FLEEING, RELOCATING }

@export var hits_to_flee: int = 4
@export var body_length: int = 4
@export var crawl_step_time: float = 0.35

var state: State = State.BLOCKING
var _tiles: Array[Vector2i] = []
var _hits := 0
var _level: Node
var _segments: Array[CentipedeSegment] = []


func _ready() -> void:
	add_to_group("centipedes")


func bind_level(level: Node) -> void:
	_level = level


## Lays out the body at `tiles` (head first) and (re)builds its segment
## visuals to match. Called once by Level._seed_centipedes() right after
## instancing and bind_level().
func spawn_at(tiles: Array[Vector2i]) -> void:
	_tiles = tiles.duplicate()
	for segment in _segments:
		if is_instance_valid(segment):
			segment.queue_free()
	_segments.clear()
	for tile in _tiles:
		var segment: CentipedeSegment = SegmentScene.instantiate()
		add_child(segment)
		segment.global_position = _level.tile_centre(tile)
		_segments.append(segment)


## Any segment being hit lands here (CentipedeSegment.take_hit() forwards to
## its parent) -- one shared counter for the whole body. A no-op once
## already FLEEING/RELOCATING, mirroring Earthworm.take_hit()'s guard
## against re-triggering mid-retreat.
func take_hit() -> void:
	if state != State.BLOCKING:
		return
	_hits += 1
	if _hits >= hits_to_flee:
		_begin_flee()


func _begin_flee() -> void:
	state = State.FLEEING


## The live Centipede whose body occupies `tile`, or null. Mirrors
## Blockade.at_tile()'s shape but deliberately drops the `tile_size`
## parameter Blockade takes: Blockade only stores `global_position` and
## needs `tile_size` to convert it back to a tile coordinate for comparison,
## but Centipede already stores `_tiles` directly (the whole body's single
## source of truth), so no conversion is needed here.
static func segment_at_tile(tree: SceneTree, tile: Vector2i) -> Centipede:
	for node in tree.get_nodes_in_group("centipedes"):
		var centipede := node as Centipede
		if centipede != null and tile in centipede._tiles:
			return centipede
	return null
```

Create `entities/centipede/centipede.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://entities/centipede/centipede.gd" id="1_cent"]

[node name="Centipede" type="Node2D"]
script = ExtResource("1_cent")
```

In `world/level.gd`, modify `is_blocked()`:

```gdscript
func is_blocked(tile: Vector2i, plane: Layer) -> bool:
	if maze == null:
		return true
	if Blockade.at_tile(get_tree(), tile, TILE_SIZE) != null:
		return true
	if Centipede.segment_at_tile(get_tree(), tile) != null:
		return true
	if plane == Layer.CEILING:
		return ceiling.is_blocked(tile.x, tile.y)
	return maze.is_ground_blocked(tile.x, tile.y)
```

In `world/level.gd`, add a new method right after `_tile_centre()`:

```gdscript
## Public wrapper for _tile_centre() -- Level exposes the one seam external
## production code should read tile positions through, rather than reaching
## into the underscore-prefixed internal helper directly (see
## is_water_at()'s identical rationale, added in a later task). Centipede
## uses this to position its segments; _tile_centre() itself stays the
## internal implementation every other in-file caller already uses
## directly.
func tile_centre(tile: Vector2i) -> Vector2:
	return _tile_centre(tile.x, tile.y)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Run the full suite once** (this task touches a shared file, `Level`)

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add entities/centipede/centipede.gd entities/centipede/centipede.tscn world/level.gd tests/test_centipede.gd
git status # stage a stray .gd.uid/.tscn.uid if one appears
git commit -m "Centipede: tile-array data model, shared hit counter, dual-plane blocking"
```

---

### Task 3: Combat integration — Player and Enemy melee hit a Centipede

**Files:**
- Modify: `entities/player/player.gd`
- Modify: `entities/enemy/enemy.gd`
- Test: `tests/test_melee.gd` (extend)
- Test: `tests/test_enemy_centipede_melee.gd` (new)

**Interfaces:**
- Consumes: `Centipede.segment_at_tile()`, `Centipede.take_hit()` (Task 2).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_melee.gd` (reusing its existing `_make_player()` helper exactly):

```gdscript
func test_melee_hits_a_centipede_in_range() -> void:
	var player := _make_player()
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	var target_tile: Vector2i = player._mover.committed_tile() + Vector2i(int(player.facing.x), int(player.facing.y))
	centipede.spawn_at([target_tile])

	player._melee()

	assert_eq(centipede._hits, 1, "the swing landed one hit on the centipede")


func test_melee_costs_hunger_when_it_lands_on_a_centipede() -> void:
	var player := _make_player()
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	var target_tile: Vector2i = player._mover.committed_tile() + Vector2i(int(player.facing.x), int(player.facing.y))
	centipede.spawn_at([target_tile])
	var before := player.hunger.current_hunger

	player._melee()

	assert_almost_eq(player.hunger.current_hunger, before + player.melee_hunger_cost, 0.001,
		"a landed hit on a centipede costs hunger like any other landed melee hit")
```

Create `tests/test_enemy_centipede_melee.gd`:

```gdscript
extends GutTest
## Enemy's opportunistic melee against a Centipede (sub-project H): mirrors
## _melee_nearby_hatchling() in spirit (an "opportunistic swing that isn't
## Enemy's tracked CHASE target") but uses an exact-tile lookup instead of a
## distance threshold, since Centipede.segment_at_tile() -- like
## Blockade.at_tile(), which Player._melee() already uses the same way --
## isn't a Hurtbox-bearing target _melee_target() can reach.

const EnemyScene := preload("res://entities/enemy/enemy.tscn")


func _make_enemy() -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(500, 500)
	return enemy


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_centipede_at(level: Level, tile: Vector2i) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at([tile])
	return centipede


func test_melees_a_centipede_on_the_tile_ahead() -> void:
	var enemy := _make_enemy()
	var level := _make_level()
	var target_tile: Vector2i = enemy._mover.committed_tile() + Vector2i(int(enemy.facing.x), int(enemy.facing.y))
	var centipede := _make_centipede_at(level, target_tile)

	enemy._melee_nearby_centipede()

	assert_eq(centipede._hits, 1, "the swing landed one hit on the centipede ahead")


func test_ignores_a_centipede_not_on_the_tile_ahead() -> void:
	var enemy := _make_enemy()
	var level := _make_level()
	var far_tile: Vector2i = enemy._mover.committed_tile() + Vector2i(5, 5)
	var centipede := _make_centipede_at(level, far_tile)

	enemy._melee_nearby_centipede()

	assert_eq(centipede._hits, 0, "a centipede not on the exact tile ahead is untouched")


func test_respects_the_shared_melee_cooldown() -> void:
	var enemy := _make_enemy()
	var level := _make_level()
	var target_tile: Vector2i = enemy._mover.committed_tile() + Vector2i(int(enemy.facing.x), int(enemy.facing.y))
	var centipede := _make_centipede_at(level, target_tile)
	enemy._melee_left = 1.0 # already on cooldown from another swing this frame

	enemy._melee_nearby_centipede()

	assert_eq(centipede._hits, 0, "no swing while the shared melee cooldown is still active")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_melee.gd 2>&1`
Expected: FAIL — the two new tests fail (nothing in `Player._melee()` hits a Centipede yet).

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_centipede_melee.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function '_melee_nearby_centipede'`.

- [ ] **Step 3: Write the implementation**

In `entities/player/player.gd`, in `_melee()`, add a new check right after the existing Blockade block (before the `earthworms` group-scan block, which stays untouched until this plan's final task):

```gdscript
	var target_tile := _mover.committed_tile() + Vector2i(int(facing.x), int(facing.y))
	var blockade := Blockade.at_tile(get_tree(), target_tile, _mover.tile_size)
	if blockade != null:
		blockade.take_hit(facing)
		HungerComponent.charge_all(get_tree(), melee_hunger_cost)
		return
	var centipede := Centipede.segment_at_tile(get_tree(), target_tile)
	if centipede != null:
		centipede.take_hit()
		HungerComponent.charge_all(get_tree(), melee_hunger_cost)
		return
	for node in get_tree().get_nodes_in_group("earthworms"):
		var worm := node as Node2D
		if worm == null or worm.global_position.distance_to(target) > melee_range:
			continue
		if worm.has_method("take_hit"):
			worm.take_hit()
		HungerComponent.charge_all(get_tree(), melee_hunger_cost)
		return
```

In `entities/enemy/enemy.gd`, add a new method right after `_melee_nearby_hatchling()`:

```gdscript
## Opportunistic strike, mirroring _melee_nearby_hatchling() but for a
## Centipede: Player._melee() already hits a Centipede via an exact-tile
## lookup (the tile directly ahead, same as its existing Blockade check)
## because neither carries a Hurtbox _melee_target() could reach -- Enemy
## needs the identical tile-based check, not the distance-based one
## _melee_nearby_hatchling() uses.
func _melee_nearby_centipede() -> void:
	if _melee_left > 0.0:
		return
	var target_tile := _mover.committed_tile() + Vector2i(int(facing.x), int(facing.y))
	var centipede := Centipede.segment_at_tile(get_tree(), target_tile)
	if centipede == null:
		return
	_melee_left = melee_cooldown
	centipede.take_hit()
	HungerComponent.charge_all(get_tree(), melee_hunger_cost)
```

In `entities/enemy/enemy.gd`, in `_physics_process()`, add the new call right after the existing one:

```gdscript
		_melee_nearby_hatchling()
		_melee_nearby_centipede()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_melee.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_centipede_melee.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add entities/player/player.gd entities/enemy/enemy.gd tests/test_melee.gd tests/test_enemy_centipede_melee.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Player + Enemy melee hit a Centipede via an exact-tile lookup"
```

---

### Task 4: `Level.is_water_at()` + `Centipede`'s local BFS pathfinding

**Files:**
- Modify: `world/level.gd`
- Modify: `entities/centipede/centipede.gd`
- Test: `tests/test_centipede_pathing.gd` (new)

**Interfaces:**
- Produces: `Level.is_water_at(tile: Vector2i) -> bool` (consumed by this task and Task 7), `Centipede._find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]` (consumed by Task 5).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_centipede_pathing.gd`:

```gdscript
extends GutTest
## Centipede's local BFS (sub-project H, design §6): avoids walls, water,
## and the body's own trailing tiles; returns [] when unreachable. Tested
## directly (no timers involved yet -- the crawl stepper that calls this on
## a schedule is a later task). Uses dynamically-derived open cells rather
## than hardcoded coordinates for multi-tile scenarios, since the maze
## layout between odd/odd cell-centres isn't guaranteed by MazeData's own
## contract -- only that all open cells are mutually reachable.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


func test_find_path_returns_just_the_start_when_already_there() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	var path := centipede._find_path(start, start)
	assert_eq(path, [start])


func test_find_path_finds_a_route_between_two_open_cells() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var goal: Vector2i = cells[cells.size() - 1]
	var centipede := _make_centipede(level, [start])

	var path := centipede._find_path(start, goal)

	assert_eq(path[0], start)
	assert_eq(path[path.size() - 1], goal, "every open cell is mutually reachable")


func test_find_path_avoids_a_flooded_intermediate_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var goal: Vector2i = cells[cells.size() - 1]
	var centipede := _make_centipede(level, [start])
	var dry_path := centipede._find_path(start, goal)
	assert_gt(dry_path.size(), 2, "sanity: needs at least one intermediate tile to flood")
	var blocked_tile: Vector2i = dry_path[1]
	level.set_water_at(blocked_tile, true)

	var wet_path := centipede._find_path(start, goal)

	assert_false(blocked_tile in wet_path, "the newly-flooded tile is never stepped on")


func test_find_path_returns_empty_when_completely_sealed_in() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		level.set_water_at(start + dir, true) # no-ops harmlessly on any neighbor that's already a wall
	var centipede := _make_centipede(level, [start])

	var path := centipede._find_path(start, cells[cells.size() - 1])

	assert_eq(path, [], "every neighbor is either a wall or now flooded -- nowhere to go")


func test_find_path_never_steps_on_the_bodys_own_trailing_tiles() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var second_segment := Vector2i.ZERO
	var found_neighbor := false
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var candidate: Vector2i = start + dir
		if level.maze.is_open(candidate.x, candidate.y):
			second_segment = candidate
			found_neighbor = true
			break
	assert_true(found_neighbor, "sanity: the maze must have at least one open neighbor here")
	var centipede := _make_centipede(level, [start, second_segment])
	var goal: Vector2i = cells[cells.size() - 1]
	if goal == second_segment:
		goal = cells[cells.size() - 2]

	var path := centipede._find_path(start, goal)

	assert_false(second_segment in path, "the body's own second segment is never stepped on")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_pathing.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function '_find_path'`.

- [ ] **Step 3: Write the implementation**

In `world/level.gd`, add a new method right after `set_water_at()`:

```gdscript
## Public accessor for water-tile state -- until now _water_tiles was only
## ever read from inside Level itself or directly by tests; Centipede's
## pathing is the first production consumer outside Level, so it gets the
## same one-entry-point treatment as set_water_at()/patch_pit_at() rather
## than reaching into the underscore-prefixed dict directly.
func is_water_at(tile: Vector2i) -> bool:
	return _water_tiles.has(tile)
```

In `entities/centipede/centipede.gd`, add a new method after `segment_at_tile()`:

```gdscript
## Local BFS from `from` to `to` (design §6): a tile is passable if it's
## open, not flooded, and not currently occupied by this body's own
## trailing tiles (so a crawl step never tries to path through itself).
## Deliberately separate from the shared Enemy/Player AStar (Level._astar/
## GridNav) -- that grid doesn't treat water as solid at all today, and
## Centipede's own pathing needs (reach a boundary tile, reach a fresh spot)
## are much simpler than Enemy's chase-a-moving-target. Returns [] if
## unreachable.
func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return [from]
	var occupied := {}
	for tile in _tiles:
		occupied[tile] = true
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var came_from := {from: from}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == to:
			break
		for dir in dirs:
			var next: Vector2i = current + dir
			if came_from.has(next):
				continue
			if not _level.maze.is_open(next.x, next.y):
				continue
			if _level.is_water_at(next):
				continue
			if occupied.has(next):
				continue
			came_from[next] = current
			frontier.append(next)
	if not came_from.has(to):
		return []
	var path: Array[Vector2i] = [to]
	var walk: Vector2i = to
	while walk != from:
		walk = came_from[walk]
		path.append(walk)
	path.reverse()
	return path
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_pathing.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add world/level.gd entities/centipede/centipede.gd tests/test_centipede_pathing.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Level.is_water_at() + Centipede's local water-avoiding BFS"
```

---

### Task 5: Crawl stepper — flee movement, occupant destruction, despawn

**Files:**
- Modify: `entities/centipede/centipede.gd`
- Test: `tests/test_centipede_crawl.gd` (new)

**Interfaces:**
- Consumes: `Centipede._find_path()` (Task 4), `Level._destroy_occupants_at()` (pre-existing, sub-project G), `Level.tile_centre()` (Task 2).
- Produces: `Centipede._crawl_step() -> void`, `Centipede._start_crawl() -> void`, `Centipede._begin_flee()` (now fully wired to actually move), consumed as-is by Task 6 (which extends `_start_crawl()`) and Task 7 (which reuses the same crawl stepper for relocating).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_centipede_crawl.gd`:

```gdscript
extends GutTest
## Centipede's crawl stepper (sub-project H, design §5): the shared engine
## both FLEEING (retreat to the map boundary, despawn) and RELOCATING
## (flood-forced move to a fresh spot, resume BLOCKING) drive. Tested by
## calling _crawl_step() directly, never by awaiting the real
## crawl_step_time SceneTreeTimer -- mirrors how sub-project G's
## WaterIngress tested _flood_ring/_drain_ring directly rather than through
## their real timer scheduling.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


func test_crawl_step_advances_the_head_and_shifts_the_tail() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	var expected_next: Vector2i = centipede._path[1]

	centipede._crawl_step()

	assert_eq(centipede._tiles[0], expected_next, "the head moved to the next path tile")


func test_crawl_step_repositions_segments_to_match_the_new_tiles() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()

	centipede._crawl_step()

	assert_eq(centipede._segments[0].global_position, level.tile_centre(centipede._tiles[0]))


func test_crawl_step_destroys_a_larva_on_the_newly_entered_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	var next_tile: Vector2i = centipede._path[1]
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	level.add_child(larva)
	larva.global_position = level.tile_centre(next_tile)

	centipede._crawl_step()

	assert_true(larva.is_queued_for_deletion(), "a larva on the tile the head just entered is destroyed")


func test_arriving_at_the_target_while_fleeing_frees_the_centipede() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede.state = Centipede.State.FLEEING
	centipede._target = start # already there -- one call should arrive immediately
	centipede._path = [start]

	centipede._crawl_step()

	assert_true(centipede.is_queued_for_deletion(), "fleeing that reaches its target despawns")


func test_arriving_at_the_target_while_relocating_returns_to_blocking() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede.state = Centipede.State.RELOCATING
	centipede._target = start
	centipede._path = [start]

	centipede._crawl_step()

	assert_eq(centipede.state, Centipede.State.BLOCKING, "relocating that arrives resumes blocking in place")


func test_crawl_step_is_a_noop_on_a_freed_level() -> void:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])
	centipede.state = Centipede.State.FLEEING
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	level.queue_free()
	await get_tree().process_frame

	centipede._crawl_step() # must not error on a freed level

	assert_true(true, "reached this point without erroring")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_crawl.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function '_start_crawl'` (or `_crawl_step`).

- [ ] **Step 3: Write the implementation**

In `entities/centipede/centipede.gd`, add new instance vars near the existing ones:

```gdscript
var _target: Vector2i
var _path: Array[Vector2i] = []
```

Replace `_begin_flee()`:

```gdscript
func _begin_flee() -> void:
	state = State.FLEEING
	_target = _nearest_boundary_tile()
	_start_crawl()
	_schedule_next_step()
```

Add new methods after `_begin_flee()`:

```gdscript
## Closest of the four map edges to the current head, as a real tile
## coordinate (not a raw direction -- unlike Earthworm's own
## _direction_to_nearest_boundary(), which moved in a straight line that
## could clip through walls, this feeds a real wall-aware BFS target).
func _nearest_boundary_tile() -> Vector2i:
	var head: Vector2i = _tiles[0]
	var maze := _level.maze
	var candidates: Dictionary = {
		Vector2i(0, head.y): head.x,
		Vector2i(maze.width - 1, head.y): maze.width - 1 - head.x,
		Vector2i(head.x, 0): head.y,
		Vector2i(head.x, maze.height - 1): maze.height - 1 - head.y,
	}
	var best_tile: Vector2i = Vector2i(0, head.y)
	var best_dist := INF
	for tile in candidates:
		if candidates[tile] < best_dist:
			best_dist = candidates[tile]
			best_tile = tile
	return best_tile


func _start_crawl() -> void:
	_path = _find_path(_tiles[0], _target)


## Schedules one crawl tick crawl_step_time seconds from now, real-timer-
## paced like WaterIngress's own ring scheduling (not per-frame movement --
## this is a slow, deliberate crawl, not player-speed motion).
func _schedule_next_step() -> void:
	if _level == null or not is_instance_valid(_level):
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(crawl_step_time).timeout.connect(_crawl_step)


func _crawl_step() -> void:
	if state == State.BLOCKING or _level == null or not is_instance_valid(_level):
		return
	if _path.is_empty():
		# Nowhere to go yet (e.g. still boxed in) -- retry the search next
		# tick rather than freezing or falsely "arriving".
		_start_crawl()
		_schedule_next_step()
		return
	if _path.size() == 1:
		_arrive()
		return
	var next_tile: Vector2i = _path[1]
	if not _level.maze.is_open(next_tile.x, next_tile.y) or _level.is_water_at(next_tile):
		# Something changed underfoot mid-crawl (e.g. a fresh flood) --
		# recompute from where we are now instead of stepping into it.
		_start_crawl()
		_schedule_next_step()
		return
	_level._destroy_occupants_at(next_tile)
	_tiles.push_front(next_tile)
	_tiles.pop_back()
	_sync_segments()
	_path.remove_at(0)
	if next_tile == _target:
		_arrive()
	else:
		_schedule_next_step()


func _arrive() -> void:
	if state == State.FLEEING:
		queue_free()
	elif state == State.RELOCATING:
		state = State.BLOCKING


func _sync_segments() -> void:
	for i in _segments.size():
		if i < _tiles.size():
			_segments[i].global_position = _level.tile_centre(_tiles[i])
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_crawl.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Run the full suite once**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add entities/centipede/centipede.gd tests/test_centipede_crawl.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Centipede: crawl stepper drives real flee movement to the boundary"
```

---

### Task 6: Boxed-in tunnel fallback

**Files:**
- Modify: `entities/centipede/centipede.gd`
- Test: `tests/test_centipede_tunnel_fallback.gd` (new)

**Interfaces:**
- Consumes: `Centipede._find_path()` (Task 4), `Level.dev_remove_wall_at()`, `Level.is_boundary()` (pre-existing).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_centipede_tunnel_fallback.gd`:

```gdscript
extends GutTest
## Centipede's boxed-in tunnel fallback (sub-project H, design §6): when no
## open+dry path exists to the target, it carves the single best adjacent
## wall tile and retries -- the "escape-through-tunnels... unless blocked
## in" case from the roadmap's original phrasing.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


func _seal_in(level: Level, tile: Vector2i) -> void:
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		level.set_water_at(tile + dir, true) # no-ops harmlessly on an already-wall neighbor


func test_tunnel_toward_carves_exactly_one_wall_tile_when_boxed_in() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	_seal_in(level, start)
	var centipede := _make_centipede(level, [start])
	var open_before := level.maze.open_cells().size()

	var carved := centipede._tunnel_toward(cells[cells.size() - 1])

	assert_true(carved)
	assert_eq(level.maze.open_cells().size(), open_before + 1, "exactly one new tile was carved open")


func test_tunnel_toward_never_carves_a_boundary_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	_seal_in(level, start)
	var centipede := _make_centipede(level, [start])
	var before: Dictionary = {}
	for cell in level.maze.open_cells():
		before[cell] = true

	centipede._tunnel_toward(cells[cells.size() - 1])

	for cell in level.maze.open_cells():
		if not before.has(cell):
			assert_false(level.is_boundary(cell), "the newly carved tile is never on the boundary")


func test_start_crawl_finds_a_path_after_tunneling_through_when_boxed_in() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	_seal_in(level, start)
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]

	centipede._start_crawl()

	assert_false(centipede._path.is_empty(), "boxed-in start_crawl tunnels through and finds a path")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_tunnel_fallback.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function '_tunnel_toward'`.

- [ ] **Step 3: Write the implementation**

In `entities/centipede/centipede.gd`, replace `_start_crawl()`:

```gdscript
## Boxed-in fallback (design §6): if no open+dry path exists, carve the
## single adjacent non-boundary wall tile that most shortens the remaining
## distance to `target`, then retry. If even that finds no candidate (fully
## enclosed by the map boundary -- extremely unlikely), _path stays empty;
## _crawl_step()'s own empty-path branch retries this same search again
## next tick rather than freezing or falsely "arriving".
func _start_crawl() -> void:
	_path = _find_path(_tiles[0], _target)
	if _path.is_empty() and _tunnel_toward(_target):
		_path = _find_path(_tiles[0], _target)
```

Add a new method after `_start_crawl()`:

```gdscript
## Finds the adjacent (4-directional from the current head) wall tile that
## minimizes remaining Manhattan distance to `target`, excluding any
## boundary tile from candidacy -- the same caller-side guardrail check
## RemoveWallsSkill/SeismicCompaction both perform before touching wall
## geometry (Level.dev_remove_wall_at() itself enforces no such
## restriction; it's the unrestricted dev cheat). Carves the chosen tile
## open. Returns false if no non-boundary wall candidate exists.
func _tunnel_toward(target: Vector2i) -> bool:
	var head: Vector2i = _tiles[0]
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var best_tile := Vector2i.ZERO
	var best_dist := INF
	var found := false
	for dir in dirs:
		var candidate: Vector2i = head + dir
		if _level.is_boundary(candidate):
			continue
		if _level.maze.is_open(candidate.x, candidate.y):
			continue
		var dist := absi(candidate.x - target.x) + absi(candidate.y - target.y)
		if dist < best_dist:
			best_dist = dist
			best_tile = candidate
			found = true
	if not found:
		return false
	_level.dev_remove_wall_at(best_tile)
	return true
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_tunnel_fallback.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Run the full suite once**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add entities/centipede/centipede.gd tests/test_centipede_tunnel_fallback.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Centipede: boxed-in tunnel fallback carves through a wall"
```

---

### Task 7: Water-flood relocate

**Files:**
- Modify: `world/level.gd`
- Modify: `entities/centipede/centipede.gd`
- Test: `tests/test_centipede_relocate.gd` (new)

**Interfaces:**
- Consumes: `Centipede.segment_at_tile()` (Task 2), `Centipede._start_crawl()`/`_schedule_next_step()` (Tasks 5-6).
- Produces: `Centipede.notify_flooded() -> void`, `Level._flood_centipedes_at(tile: Vector2i) -> void` (private, wired into `set_water_at()`).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_centipede_relocate.gd`:

```gdscript
extends GutTest
## Centipede's flood-provoked relocate (sub-project H, design §5): distinct
## from a combat-provoked flee -- it picks a fresh dry spot and resumes
## BLOCKING there instead of despawning at the boundary.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


func test_notify_flooded_transitions_to_relocating() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])

	centipede.notify_flooded()

	assert_eq(centipede.state, Centipede.State.RELOCATING)


func test_notify_flooded_is_a_noop_while_already_fleeing() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])
	centipede.state = Centipede.State.FLEEING

	centipede.notify_flooded()

	assert_eq(centipede.state, Centipede.State.FLEEING, "already fleeing takes priority")


func test_pick_relocate_target_never_picks_a_flooded_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	for cell in cells:
		if cell != start:
			level.set_water_at(cell, true)

	var target := centipede._pick_relocate_target()

	assert_eq(target, start, "every other open tile is flooded -- nowhere valid, so it stays put")


func test_level_set_water_at_notifies_an_occupying_centipede() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])

	level.set_water_at(start, true)

	assert_eq(centipede.state, Centipede.State.RELOCATING, "flooding the tile it occupies triggers a relocate")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_relocate.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'notify_flooded'`.

- [ ] **Step 3: Write the implementation**

In `entities/centipede/centipede.gd`, add new methods after `_arrive()`:

```gdscript
## Called by Level (via _flood_centipedes_at()) when a tile this body
## occupies just got flooded. A no-op unless currently BLOCKING -- already
## FLEEING/RELOCATING takes priority, mirrors take_hit()'s own guard.
func notify_flooded() -> void:
	if state != State.BLOCKING:
		return
	var destination := _pick_relocate_target()
	if destination == _tiles[0]:
		return # nowhere dry to go -- stay put, a later flood event will try again
	state = State.RELOCATING
	_target = destination
	_start_crawl()
	_schedule_next_step()


## A random open, dry, non-boundary tile not already part of this body --
## the crawl stepper naturally reforms the body as the tail of whatever
## path the head walks to reach it (snake-style), so this only needs to
## pick a single destination tile, not a pre-formed chain (unlike the
## initial spawn placement in Level._seed_centipedes(), which does need a
## pre-formed chain since there's no crawl to lay one out at spawn time).
## Returns the current head tile itself if nothing valid is found --
## notify_flooded() reads that as "stay put".
func _pick_relocate_target() -> Vector2i:
	var head: Vector2i = _tiles[0]
	var occupied := {}
	for tile in _tiles:
		occupied[tile] = true
	var candidates := _level.maze.open_cells().duplicate()
	candidates.shuffle()
	for candidate in candidates:
		if occupied.has(candidate):
			continue
		if _level.is_water_at(candidate):
			continue
		if _level.is_boundary(candidate):
			continue
		return candidate
	return head
```

In `world/level.gd`, add a new method right after `_resurface_items_at()`:

```gdscript
## Sweeps active Centipedes for one occupying `tile` and tells it the tile
## just flooded -- mirrors _drown_traps_at()/_submerge_items_at()'s shape,
## called from set_water_at()'s flood branch alongside them.
func _flood_centipedes_at(tile: Vector2i) -> void:
	var centipede := Centipede.segment_at_tile(get_tree(), tile)
	if centipede != null:
		centipede.notify_flooded()
```

In `world/level.gd`, modify `set_water_at()`'s flood branch:

```gdscript
	if value:
		_water_tiles[tile] = true
		if not _water_nodes.has(tile):
			_water_nodes[tile] = _spawn_water_marker(tile)
		_drown_traps_at(tile)
		_submerge_items_at(tile)
		_flood_centipedes_at(tile)
	else:
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_centipede_relocate.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Run the full suite once** (this task touches a shared file, `Level`)

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add world/level.gd entities/centipede/centipede.gd tests/test_centipede_relocate.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Centipede: flood-provoked relocate to a fresh dry spot"
```

---

### Task 8: `Level._seed_centipedes()` — spawn placement

**Files:**
- Modify: `world/level.gd`
- Test: `tests/test_level_centipede_seeding.gd` (new)

**Interfaces:**
- Consumes: `Centipede.spawn_at()`, `Centipede.bind_level()` (Task 2).
- Produces: `Level.CENTIPEDE_COUNT`, `Level._find_open_chain(length: int, reserved: Dictionary) -> Array[Vector2i]` (private).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_level_centipede_seeding.gd`:

```gdscript
extends GutTest
## Level's Centipede seeding (sub-project H): a connected chain of
## body_length open tiles, reserved away from both spawns. Mirrors
## test_level_world_seeding.gd's earthworm-seeding test in spirit -- that
## file's own earthworm test is removed in this plan's final task alongside
## Earthworm's full deletion.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_seeds_the_expected_number_of_centipedes() -> void:
	var level := _make_level()
	var centipedes := level.get_tree().get_nodes_in_group("centipedes")
	assert_eq(centipedes.size(), Level.CENTIPEDE_COUNT)


func test_seeded_centipede_body_is_a_connected_chain() -> void:
	var level := _make_level()
	var centipedes := level.get_tree().get_nodes_in_group("centipedes")
	var centipede := centipedes[0] as Centipede
	assert_eq(centipede._tiles.size(), centipede.body_length)
	for i in range(1, centipede._tiles.size()):
		var a: Vector2i = centipede._tiles[i - 1]
		var b: Vector2i = centipede._tiles[i]
		var dist := absi(a.x - b.x) + absi(a.y - b.y)
		assert_eq(dist, 1, "consecutive body tiles are always orthogonally adjacent")


func test_seeded_centipede_is_away_from_both_spawns() -> void:
	var level := _make_level()
	var player_tile := level.tile_of(level.player.global_position)
	var enemy_tile := level.tile_of(level.enemy.global_position)
	var centipedes := level.get_tree().get_nodes_in_group("centipedes")
	var centipede := centipedes[0] as Centipede
	for tile in centipede._tiles:
		assert_ne(tile, player_tile)
		assert_ne(tile, enemy_tile)


func test_find_open_chain_never_includes_a_boundary_tile() -> void:
	var level := _make_level()
	var chain := level._find_open_chain(4, {})
	for tile in chain:
		assert_false(level.maze.is_boundary(tile.x, tile.y))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_centipede_seeding.gd 2>&1`
Expected: FAIL — `Invalid get index 'CENTIPEDE_COUNT'` or similar, since it doesn't exist yet.

- [ ] **Step 3: Write the implementation**

In `world/level.gd`, add new consts near `const EARTHWORM_COUNT := 1`:

```gdscript
const CENTIPEDE_COUNT := 1
const CentipedeScene := preload("res://entities/centipede/centipede.tscn")
```

In `world/level.gd`, in `build()`, add the new call right after `_seed_earthworms()`:

```gdscript
	_seed_earthworms()
	_seed_centipedes()
```

In `world/level.gd`, add new methods right after `_seed_earthworms()`:

```gdscript
## Seed a Centipede obstacle (sub-project H): a connected, in-bounds,
## non-boundary chain of body_length open tiles, reserved away from both
## spawns. Skips spawning entirely if no valid chain exists (graceful
## degradation, matching WaterIngress's own no-op-on-empty-maze precedent)
## -- this can legitimately happen on a very cramped maze.
func _seed_centipedes() -> void:
	var reserved := {tile_of(player.global_position): true, tile_of(enemy.global_position): true}
	for i in CENTIPEDE_COUNT:
		var centipede: Centipede = CentipedeScene.instantiate()
		var chain := _find_open_chain(centipede.body_length, reserved)
		if chain.is_empty():
			centipede.free()
			continue
		_entities.add_child(centipede)
		centipede.bind_level(self)
		centipede.spawn_at(chain)
		for tile in chain:
			reserved[tile] = true


## A randomized-walk search for a connected chain of `length` open,
## non-boundary tiles, none of which are in `reserved`. Backtracks (starts
## a fresh walk from a new candidate) on a dead end rather than giving up
## immediately -- a single greedy walk from an unlucky starting tile could
## dead-end long before reaching `length` even in a maze with plenty of
## room elsewhere. Returns [] if no candidate start produces a full chain.
func _find_open_chain(length: int, reserved: Dictionary) -> Array[Vector2i]:
	var starts := maze.open_cells()
	starts.shuffle()
	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for start in starts:
		if reserved.has(start) or maze.is_boundary(start.x, start.y):
			continue
		var chain: Array[Vector2i] = [start]
		var in_chain := {start: true}
		while chain.size() < length:
			var options: Array[Vector2i] = []
			for dir in dirs:
				var candidate: Vector2i = chain[chain.size() - 1] + dir
				if in_chain.has(candidate) or reserved.has(candidate):
					continue
				if not maze.is_open(candidate.x, candidate.y) or maze.is_boundary(candidate.x, candidate.y):
					continue
				options.append(candidate)
			if options.is_empty():
				break
			options.shuffle()
			var next: Vector2i = options[0]
			chain.append(next)
			in_chain[next] = true
		if chain.size() == length:
			return chain
	return []
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_centipede_seeding.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Run the full suite once**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add world/level.gd tests/test_level_centipede_seeding.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Level._seed_centipedes(): connected-chain placement"
```

---

### Task 9: Earthworm removal + full reference cleanup

**Files:**
- Delete: `entities/earthworm/earthworm.gd`, `entities/earthworm/earthworm.tscn`, `entities/earthworm/earthworm.gd.uid`
- Delete: `tests/test_earthworm.gd`, `tests/test_earthworm.gd.uid`
- Modify: `world/level.gd`
- Modify: `entities/player/player.gd`
- Modify: `entities/larva/larva.gd`
- Modify: `resources/prey_type.gd`
- Modify: `tests/test_level_sense_and_pits.gd`
- Modify: `tests/test_level_world_seeding.gd`

**Interfaces:**
- None (pure cleanup — every consumer of `Earthworm`/`"earthworms"` was already given a `Centipede` equivalent in Tasks 1-8).

- [ ] **Step 1: Delete Earthworm's own files**

```bash
git rm entities/earthworm/earthworm.gd entities/earthworm/earthworm.tscn entities/earthworm/earthworm.gd.uid
git rm tests/test_earthworm.gd tests/test_earthworm.gd.uid
```

(If a `.uid` file isn't tracked by git, `git rm` will error on that specific path — in that case use a plain `rm` for it instead and continue; this is expected, not a failure.)

- [ ] **Step 2: Remove Earthworm's own seeding code from `world/level.gd`**

Remove the const block (originally at the top of the file):

```gdscript
## Earthworm obstacles seeded per depth (design §6).
const EARTHWORM_COUNT := 1
```

Remove the preload line:

```gdscript
const EarthwormScene := preload("res://entities/earthworm/earthworm.tscn")
```

Remove the call site in `build()`:

```gdscript
	_seed_earthworms()
```

(Leave the `_seed_centipedes()` call right after it in place.)

Remove the whole `_seed_earthworms()` function:

```gdscript
## Seed a handful of Earthworm obstacles (design §6) across random open,
## non-spawn tiles.
func _seed_earthworms() -> void:
	var reserved := {tile_of(player.global_position): true, tile_of(enemy.global_position): true}
	var cells := maze.open_cells()
	cells.shuffle()
	var placed := 0
	for cell in cells:
		if placed >= EARTHWORM_COUNT:
			break
		if reserved.has(cell):
			continue
		var worm := EarthwormScene.instantiate()
		worm.global_position = _tile_centre(cell.x, cell.y)
		worm.bind_level(self)
		_entities.add_child(worm)
		placed += 1
```

- [ ] **Step 3: Remove the stale "earthworms" Sense entry from `world/level.gd`**

Change `SENSE_POINT_HALF_SIZE`:

```gdscript
const SENSE_POINT_HALF_SIZE := {
	"world_items": Vector2(9, 9),
	"centipede_segments": Vector2(20, 20),
}
```

- [ ] **Step 4: Fix the remaining stale "earthworm" doc comments in `world/level.gd`**

Change:

```gdscript
## spiders/larvae/traps get the real outline shader; walls/pits (no per-tile
## sprite to shader-outline — the whole maze is one batched MazeRenderer
## draw) get a hand-drawn boundary trace in the same colour; items/
## earthworms (placeholder `_draw()`-only visuals, no sprite either) get a
## hand-drawn box outline in the same colour. One visual language, not three.
```

to:

```gdscript
## spiders/larvae/traps get the real outline shader; walls/pits (no per-tile
## sprite to shader-outline — the whole maze is one batched MazeRenderer
## draw) get a hand-drawn boundary trace in the same colour; items/
## Centipede segments (placeholder `_draw()`-only visuals, no sprite either)
## get a hand-drawn box outline in the same colour. One visual language, not
## three.
```

Change:

```gdscript
## Sense's point-entity outline (items, earthworms — placeholder `_draw()`-
## only visuals with no sprite for the shader technique): a simple box
## stroke, parented directly to the sensed entity so it moves for free.
```

to:

```gdscript
## Sense's point-entity outline (items, Centipede segments — placeholder
## `_draw()`-only visuals with no sprite for the shader technique): a
## simple box stroke, parented directly to the sensed entity so it moves
## for free.
```

Change:

```gdscript
## Point entity (item/earthworm) currently highlighted via Sense -> its
## highlight node (a child of the entity itself, so it moves for free).
```

to:

```gdscript
## Point entity (item/Centipede segment) currently highlighted via Sense ->
## its highlight node (a child of the entity itself, so it moves for free).
```

Change:

```gdscript
## Sense's outline cue (design round 2): "sensed", not "seen" — every
## spider/larvae/trap within `radius` of the player gets the shared outline
## shader; wall/pit tiles get a hand-drawn boundary trace; item/earthworm
## placeholders get a hand-drawn box outline. Everything Sense reveals reads
```

to:

```gdscript
## Sense's outline cue (design round 2): "sensed", not "seen" — every
## spider/larvae/trap within `radius` of the player gets the shared outline
## shader; wall/pit tiles get a hand-drawn boundary trace; item/Centipede-
## segment placeholders get a hand-drawn box outline. Everything Sense reveals reads
```

Change:

```gdscript
## World items and earthworms are placeholder `_draw()`-only visuals (no
## sprite/texture for the shader technique) — they get a hand-drawn box
```

to:

```gdscript
## World items and Centipede segments are placeholder `_draw()`-only
## visuals (no sprite/texture for the shader technique) — they get a
## hand-drawn box
```

- [ ] **Step 5: Remove Earthworm's melee block from `entities/player/player.gd`**

Remove:

```gdscript
	for node in get_tree().get_nodes_in_group("earthworms"):
		var worm := node as Node2D
		if worm == null or worm.global_position.distance_to(target) > melee_range:
			continue
		if worm.has_method("take_hit"):
			worm.take_hit()
		HungerComponent.charge_all(get_tree(), melee_hunger_cost)
		return
```

(The `Centipede` check added in Task 3 stays; this leaves the whole tile-based Blockade/Centipede pair as the final two checks in `_melee()`.)

- [ ] **Step 6: Fix the stale "Earthworm" comment in `entities/larva/larva.gd`**

Change:

```gdscript
## Called by Level right after instancing, mirroring Player/Enemy/Earthworm's
## own bind_level() — lets the larva's blocking check resolve pit/water
## hazards without the maze data being handed to it directly.
```

to:

```gdscript
## Called by Level right after instancing, mirroring Player/Enemy/Centipede's
## own bind_level() — lets the larva's blocking check resolve pit/water
## hazards without the maze data being handed to it directly.
```

- [ ] **Step 7: Fix the stale "Earthworm" comment in `resources/prey_type.gd`**

Change:

```gdscript
## False marks a hazard/obstacle creature (Earthworm) that cannot be eaten at
## all — melee/web interactions with it never call satiate().
```

to:

```gdscript
## False marks a hazard/obstacle creature (Centipede) that cannot be eaten at
## all — melee/web interactions with it never call satiate().
```

- [ ] **Step 8: Remove the old Earthworm Sense test from `tests/test_level_sense_and_pits.gd`**

Remove:

```gdscript
func test_set_sense_outline_boxes_a_nearby_earthworm() -> void:
	var level := _make_level()
	var worm: Earthworm = preload("res://entities/earthworm/earthworm.tscn").instantiate()
	level.add_child(worm)
	worm.global_position = level.player.global_position

	level.set_sense_outline(true, 50.0)

	assert_true(level._sense_point_highlights.has(worm))
```

(Task 1's `test_set_sense_outline_boxes_a_nearby_centipede_segment` in the same file already covers this behavior for the new entity.)

- [ ] **Step 9: Remove the old earthworm-seeding test and fix the header comment in `tests/test_level_world_seeding.gd`**

Change the file header:

```gdscript
extends GutTest
## Level's world-item and earthworm seeding (design §5, §6): placed on
## random open, non-spawn tiles each build.
```

to:

```gdscript
extends GutTest
## Level's world-item seeding (design §5): placed on random open, non-spawn
## tiles each build. Centipede seeding has its own dedicated test file,
## tests/test_level_centipede_seeding.gd, since its placement algorithm
## (a connected chain, not a single random cell) is meaningfully different
## from a plain item drop.
```

Remove:

```gdscript
func test_seeds_earthworms_away_from_both_spawns() -> void:
	var level := _make_level()
	var player_tile := level.tile_of(level.player.global_position)
	var enemy_tile := level.tile_of(level.enemy.global_position)
	var worms := level.get_tree().get_nodes_in_group("earthworms")
	assert_eq(worms.size(), Level.EARTHWORM_COUNT)
	for worm in worms:
		var tile: Vector2i = level.tile_of((worm as Node2D).global_position)
		assert_ne(tile, player_tile)
		assert_ne(tile, enemy_tile)
```

- [ ] **Step 10: Grep for any remaining reference**

Run: `grep -rn "[Ee]arthworm" --include="*.gd" --include="*.tscn" .`
Expected: no output (aside from this plan file and the design spec, which are documentation, not code).

- [ ] **Step 11: Run the full suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!`

- [ ] **Step 12: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 13: Commit**

```bash
git add -A world/level.gd entities/player/player.gd entities/larva/larva.gd resources/prey_type.gd tests/test_level_sense_and_pits.gd tests/test_level_world_seeding.gd
git add -u entities/earthworm tests/test_earthworm.gd tests/test_earthworm.gd.uid
git status # confirm the deletions and edits are staged, nothing stray left
git commit -m "Remove Earthworm entirely -- Centipede replaces it"
```

---

## Final whole-branch pass (not a numbered task — do this after Task 9)

- Run the full GUT suite once more end-to-end.
- Manual/windowed playtest pass specifically for: a Centipede's segmented body visibly spans multiple tiles and bends around corners where placed; melee (Player and Enemy) and web-shots all register hits on any segment; enough hits makes it crawl toward the map edge and vanish, tunneling through a wall if it's boxed in; flooding its corridor makes it crawl to a new dry spot and resume blocking there, rather than despawning; it visibly blocks movement on both the ground and ceiling planes at every tile it occupies; Sense outlines it the same way it outlined Earthworm. Real timer pacing (`crawl_step_time`) is not practically unit-testable — this is the same category of gap `WaterIngress`'s `RING_STEP`/`FLOOD_DURATION` had (see memory: godot-validation-workflow) — don't skip it even though every automated test is green.
