# Blockade Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Blockade placement (it currently traps the caster at their own tile instead of placing ahead of them), make it interact deliberately with whatever's on the target tile, make it block the ceiling plane, and let Remove Walls destroy one.

**Architecture:** Reuses established idioms throughout — `GridMover.committed_tile()` (like `spider_tile_contested()`) for the enemy-spider check, `Larva.web_kill()` for crushing, a new `Blockade.at_tile()` static helper (like `WebTrap.tile_has_caught_web()`) consulted from both `Level.is_blocked()` and `RemoveWallsSkill`, and the `activate()`-override-before-`_on_activate()` pattern already established by `NetHoldSkill`/`NetShotSkill` for gating cost on eligibility.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-10-blockade-fix-design.md` — read once for full context.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1 | tail -30`
  (drop `-gselect=` for the whole suite). Expect `All tests passed!`.
- Import check after any file addition: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- This slice touches only `entities/skills/blockade_skill.gd`, `entities/skills/scenes/blockade.gd`, `entities/skills/remove_walls_skill.gd`, `world/level.gd` (one method), and their tests. No other class/system — in particular, do not touch any other skill (Sense, Camouflage, Hatchlings, Egg Mine, Silk Tunnel, Decoy) or Earthworm.

---

### Task 1: Place ahead of the caster; refuse on the enemy spider; crush a larva instead

**Files:**
- Modify: `entities/skills/blockade_skill.gd`
- Test: `tests/test_blockade_skill.gd` (new)

**Interfaces:**
- Consumes: `Level.tile_of(world: Vector2) -> Vector2i`, `Level.centre_of(tile: Vector2i) -> Vector2`, `Level.patch_pit_at(tile: Vector2i)` (all pre-existing, `world/level.gd`). `GridMover.committed_tile() -> Vector2i` (pre-existing, `components/grid_mover.gd`). `Larva.web_kill()` (pre-existing).
- Produces: nothing new consumed by later tasks in this plan (Task 2/3 add their own independent helpers).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_blockade_skill.gd`:

```gdscript
extends GutTest
## BlockadeSkill (playtest fix): places ahead of the caster, not at their own
## tile (the bug that trapped the caster inside their own barricade);
## refuses to activate at all if the enemy spider occupies the target tile;
## crushes a larva standing there instead.

const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


class FakeSpider:
	extends CharacterBody2D
	var facing := Vector2.RIGHT


func _make_skill() -> BlockadeSkill:
	var skill := BlockadeSkill.new()
	skill.blockade_scene = BlockadeScene
	add_child_autofree(skill)
	return skill


func test_places_the_blockade_ahead_of_the_caster_not_at_their_own_tile() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	var start_tile := level.tile_of(player.global_position)
	player.facing = Vector2.RIGHT

	skill._on_activate(player)

	var blockade := level.get_tree().get_first_node_in_group("blockades") as Blockade
	assert_not_null(blockade, "a blockade was placed")
	assert_eq(level.tile_of(blockade.global_position), start_tile + Vector2i(1, 0),
		"placed one tile ahead of the caster, not on top of them")
	assert_ne(level.tile_of(blockade.global_position), start_tile,
		"never placed on the caster's own tile — that's the bug being fixed")


func test_activate_refuses_when_the_enemy_spider_occupies_the_target_tile() -> void:
	var level := _make_level()
	var player := level.player as Player
	var enemy := level.get_tree().get_first_node_in_group("enemy") as Node2D
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target_tile := level.tile_of(player.global_position) + Vector2i(1, 0)
	enemy.global_position = level.centre_of(target_tile)

	var fired := skill.activate(player)

	assert_false(fired, "can't place a blockade on top of the enemy spider")
	assert_eq(level.get_tree().get_nodes_in_group("blockades").size(), 0, "nothing was placed")


func test_activate_succeeds_when_the_target_tile_is_clear() -> void:
	var level := _make_level()
	var player := level.player as Player
	var enemy := level.get_tree().get_first_node_in_group("enemy") as Node2D
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	enemy.global_position = player.global_position + Vector2(1000, 1000) # guaranteed far away — avoids flaking if the maze ever spawns it adjacent

	var fired := skill.activate(player)

	assert_true(fired)
	assert_eq(level.get_tree().get_nodes_in_group("blockades").size(), 1)


func test_crushes_a_larva_standing_on_the_target_tile() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target_tile := level.tile_of(player.global_position) + Vector2i(1, 0)
	var larva := level.get_tree().get_first_node_in_group("larvae") as Larva
	larva.global_position = level.centre_of(target_tile)
	assert_true(larva.is_in_group("larvae"))

	skill._on_activate(player)

	assert_false(larva.is_in_group("larvae"), "the larva under the blockade was crushed and killed")
	assert_eq(level.get_tree().get_nodes_in_group("blockades").size(), 1, "the blockade is still placed")


func test_a_larva_elsewhere_is_untouched() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var larva := level.get_tree().get_first_node_in_group("larvae") as Larva
	larva.global_position = player.global_position + Vector2(500, 500) # far away

	skill._on_activate(player)

	assert_true(larva.is_in_group("larvae"), "a larva far from the target tile is unaffected")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_blockade_skill.gd 2>&1 | tail -40`
Expected: FAIL — the blockade lands on the caster's own tile (not one ahead), `activate()` has no spider-occupancy gate yet, and no larva-crushing logic exists.

- [ ] **Step 3: Write the implementation**

Replace the full contents of `entities/skills/blockade_skill.gd`:

```gdscript
class_name BlockadeSkill
extends SkillComponent
## Funnel/Weaver Spider (male): deploys a destructible rock/dirt barrier one
## tile ahead of the caster (playtest fix: previously placed at the
## caster's own position, which trapped them inside their own barricade).
## Unlike WebTrap (never blocks movement, just slows), a blockade is a hard
## obstacle until destroyed. Placing one directly over a pit tile also patches
## it for ground traversal, via Level.patch_pit_at — the same mechanism the
## ceiling plane already bypasses structurally (see CeilingData).
##
## Can't be placed on top of the enemy spider (activate() refuses outright,
## charging no cost) — a larva on the target tile is crushed instead and the
## blockade is placed as normal.
##
## `blockade_scene` is a high-durability StaticBody2D — its script must call
## `setup(hits_to_destroy)`.

@export var hits_to_destroy: int = 6
@export var blockade_scene: PackedScene


func activate(source: Node) -> bool:
	var origin := source as Node2D
	if origin == null:
		return false
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null:
		return false
	var target_tile := _target_tile(origin, level)
	if _spider_occupies(target_tile, source):
		return false
	return super.activate(source)


func _on_activate(source: Node) -> void:
	if blockade_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null:
		return
	var target_tile := _target_tile(origin, level)
	_crush_larva_at(target_tile, level)
	var blockade := blockade_scene.instantiate()
	_spawn_parent(source).add_child(blockade)
	blockade.global_position = level.centre_of(target_tile)
	if blockade.has_method("setup"):
		blockade.setup(hits_to_destroy)
	level.patch_pit_at(target_tile)


## The tile directly ahead of `origin`, in its current facing direction.
func _target_tile(origin: Node2D, level: Level) -> Vector2i:
	var facing: Vector2 = origin.get("facing") if "facing" in origin else Vector2.RIGHT
	return level.tile_of(origin.global_position) + Vector2i(int(facing.x), int(facing.y))


## True if another spider (not `source`) is already committed to `tile` —
## mirrors GridMover.spider_tile_contested()'s own idiom, so a blockade can
## never be used to trap or damage the enemy spider directly.
func _spider_occupies(tile: Vector2i, source: Node) -> bool:
	for node in source.get_tree().get_nodes_in_group("spiders"):
		if node == source:
			continue
		var other := node as Node2D
		if other == null:
			continue
		var other_mover := other.get_node_or_null("GridMover") as GridMover
		if other_mover != null and other_mover.committed_tile() == tile:
			return true
	return false


## A larva standing on the target tile is crushed and killed (not eaten) the
## instant a blockade lands on it.
func _crush_larva_at(tile: Vector2i, level: Level) -> void:
	for node in level.get_tree().get_nodes_in_group("larvae"):
		var larva := node as Node2D
		if larva != null and level.tile_of(larva.global_position) == tile and larva.has_method("web_kill"):
			larva.web_kill()


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_blockade_skill.gd 2>&1 | tail -40`
Expected: `All tests passed!`, `5/5 passed`.

- [ ] **Step 5: Run the full suite and commit**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20`
Expected: `All tests passed!` (existing `Enemy`'s Weaver-class kit, which also gets a `BlockadeSkill` instance via `_make_skills()`, must be unaffected — Enemy never calls `activate()`/`_on_activate()` on it outside its own AI decision loop, which this task doesn't touch).

```bash
git add entities/skills/blockade_skill.gd tests/test_blockade_skill.gd
git commit -m "Fix Blockade to place ahead of the caster instead of trapping them"
```

---

### Task 2: Block the ceiling plane too

**Files:**
- Modify: `entities/skills/scenes/blockade.gd`
- Modify: `world/level.gd`
- Test: `tests/test_blockade.gd`, `tests/test_level_blockade_blocking.gd` (new)

**Interfaces:**
- Produces: `Blockade.at_tile(tree: SceneTree, tile: Vector2i, tile_size: int) -> Blockade` (static — Task 3 reuses this exact method).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_blockade.gd` (after the existing `test_is_on_the_world_collision_layer_so_it_blocks_like_a_wall` function):

```gdscript
func test_at_tile_finds_a_blockade_on_the_given_tile() -> void:
	var blockade := _make_blockade()
	blockade.global_position = Vector2(240, 240) # tile (5,5)
	assert_eq(Blockade.at_tile(get_tree(), Vector2i(5, 5), 48), blockade)


func test_at_tile_returns_null_for_an_empty_tile() -> void:
	var blockade := _make_blockade()
	blockade.global_position = Vector2(240, 240) # tile (5,5)
	assert_null(Blockade.at_tile(get_tree(), Vector2i(9, 9), 48))
```

Create `tests/test_level_blockade_blocking.gd`:

```gdscript
extends GutTest
## Level.is_blocked() must report a live Blockade's tile as blocked on BOTH
## planes (playtest fix: ceiling blocking previously never consulted
## physical colliders at all, so a spider on the ceiling could freely pass
## over a Blockade underneath it).

const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_a_blockade_blocks_ground() -> void:
	var level := _make_level()
	var player := level.player as Player
	var tile := level.tile_of(player.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)
	var blockade: Blockade = BlockadeScene.instantiate()
	add_child_autofree(blockade)
	blockade.global_position = level.centre_of(ahead)

	assert_true(level.is_blocked(ahead, Level.Layer.GROUND))


func test_a_blockade_blocks_the_ceiling_too() -> void:
	var level := _make_level()
	var player := level.player as Player
	var tile := level.tile_of(player.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)
	var blockade: Blockade = BlockadeScene.instantiate()
	add_child_autofree(blockade)
	blockade.global_position = level.centre_of(ahead)

	assert_true(level.is_blocked(ahead, Level.Layer.CEILING),
		"a blockade blocks the ceiling plane too — it can't be crawled over")


func test_no_blockade_leaves_the_ceiling_unaffected() -> void:
	var level := _make_level()
	var player := level.player as Player
	var tile := level.tile_of(player.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)

	assert_false(level.is_blocked(ahead, Level.Layer.CEILING), "no blockade there — ceiling is unaffected")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_blockade.gd 2>&1 | tail -30`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_blockade_blocking.gd 2>&1 | tail -30`
Expected: FAIL — `Blockade.at_tile()` doesn't exist yet; the ceiling-plane test fails because `is_blocked()` doesn't consult Blockades at all yet.

- [ ] **Step 3: Write the implementation**

In `entities/skills/scenes/blockade.gd`, add a new static method (e.g. right after `setup()`):

```gdscript
## The live Blockade sitting on `tile`, or null. Returns the node (not just a
## bool) so a caller that needs to act on it (RemoveWallsSkill destroying it,
## Task 3) doesn't have to re-scan the group a second time.
static func at_tile(tree: SceneTree, tile: Vector2i, tile_size: int) -> Blockade:
	var ts := float(tile_size)
	for node in tree.get_nodes_in_group("blockades"):
		var blockade := node as Blockade
		if blockade == null:
			continue
		var blockade_tile := Vector2i(int(floorf(blockade.global_position.x / ts)), int(floorf(blockade.global_position.y / ts)))
		if blockade_tile == tile:
			return blockade
	return null
```

In `world/level.gd`, change `is_blocked()` from:

```gdscript
func is_blocked(tile: Vector2i, plane: Layer) -> bool:
	if maze == null:
		return true
	if plane == Layer.CEILING:
		return ceiling.is_blocked(tile.x, tile.y)
	return maze.is_ground_blocked(tile.x, tile.y)
```

to:

```gdscript
func is_blocked(tile: Vector2i, plane: Layer) -> bool:
	if maze == null:
		return true
	if Blockade.at_tile(get_tree(), tile, TILE_SIZE) != null:
		return true
	if plane == Layer.CEILING:
		return ceiling.is_blocked(tile.x, tile.y)
	return maze.is_ground_blocked(tile.x, tile.y)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_blockade.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `5/5 passed`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_blockade_blocking.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `3/3 passed`.

- [ ] **Step 5: Run the full suite, import check, and commit**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20`
Expected: `All tests passed!` (in particular, `tests/test_player_ceiling_traversal.gd`'s existing pit-blocking tests must still pass — this task only adds an additional check ahead of the existing ones, never removing or altering them).

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.

```bash
git add entities/skills/scenes/blockade.gd world/level.gd tests/test_blockade.gd tests/test_level_blockade_blocking.gd
git commit -m "Make Blockade block the ceiling plane, not just the ground"
```

---

### Task 3: Remove Walls destroys a Blockade

**Files:**
- Modify: `entities/skills/scenes/blockade.gd`
- Modify: `entities/skills/remove_walls_skill.gd`
- Test: `tests/test_blockade.gd`, `tests/test_remove_walls_skill.gd` (new)

**Interfaces:**
- Consumes: `Blockade.at_tile()` (Task 2).
- Produces: `Blockade.destroy() -> void` (no other task depends on it).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_blockade.gd`:

```gdscript
func test_destroy_frees_the_blockade_regardless_of_hit_count() -> void:
	var blockade := _make_blockade()
	blockade.setup(6) # would normally take 6 hits — destroy() bypasses that entirely
	blockade.destroy()
	assert_true(blockade.is_queued_for_deletion())
```

Create `tests/test_remove_walls_skill.gd`:

```gdscript
extends GutTest
## RemoveWallsSkill (playtest fix): destroys a Blockade on its target tile
## outright instead of attempting to carve a wall there — a Blockade always
## sits on an already-open floor tile, so wall-carving would find nothing to
## remove. With no Blockade in the way, existing wall-carving behavior is
## unchanged.

const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_skill() -> RemoveWallsSkill:
	var skill := RemoveWallsSkill.new()
	add_child_autofree(skill)
	return skill


func test_destroys_a_blockade_on_the_target_tile() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target := level.tile_of(player.global_position) + Vector2i(1, 0)
	var blockade: Blockade = BlockadeScene.instantiate()
	level.get_tree().current_scene.add_child(blockade)
	blockade.global_position = level.centre_of(target)

	skill._on_activate(player)

	assert_true(blockade.is_queued_for_deletion(), "the blockade is destroyed outright")


func test_carves_a_wall_as_before_when_no_blockade_is_in_the_way() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target := level.tile_of(player.global_position) + Vector2i(1, 0)
	level.maze.set_wall(target.x, target.y)

	skill._on_activate(player)

	assert_true(level.maze.is_open(target.x, target.y), "the wall is carved open as before")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_blockade.gd 2>&1 | tail -30`
Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_remove_walls_skill.gd 2>&1 | tail -30`
Expected: FAIL — `Blockade.destroy()` doesn't exist yet; `RemoveWallsSkill` has no Blockade awareness yet (the "destroys a blockade" test fails since nothing frees it).

- [ ] **Step 3: Write the implementation**

In `entities/skills/scenes/blockade.gd`, add a new method (e.g. right after `take_hit()`):

```gdscript
## One-shot destruction, bypassing the hits_to_destroy counter entirely —
## used by RemoveWallsSkill, a single powerful utility action that removes
## a blockade outright rather than chipping at it like an attack does.
func destroy() -> void:
	queue_free()
```

In `entities/skills/remove_walls_skill.gd`, change `_on_activate()` from:

```gdscript
func _on_activate(source: Node) -> void:
	var mover := source as Node2D
	if mover == null:
		return
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null or level.maze == null:
		return
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	var target := level.tile_of(mover.global_position + facing * float(Level.TILE_SIZE))
	if level.is_boundary(target):
		return  # guardrail: the outer wall can never be destroyed this way
	level.dev_remove_wall_at(target)  # same carve mechanism, boundary-gated here
```

to:

```gdscript
func _on_activate(source: Node) -> void:
	var mover := source as Node2D
	if mover == null:
		return
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level == null or level.maze == null:
		return
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	var target := level.tile_of(mover.global_position + facing * float(Level.TILE_SIZE))
	var blockade := Blockade.at_tile(source.get_tree(), target, Level.TILE_SIZE)
	if blockade != null:
		blockade.destroy()
		return
	if level.is_boundary(target):
		return  # guardrail: the outer wall can never be destroyed this way
	level.dev_remove_wall_at(target)  # same carve mechanism, boundary-gated here
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_blockade.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `6/6 passed`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_remove_walls_skill.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `2/2 passed`.

- [ ] **Step 5: Run the full suite, import check, and commit**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20`
Expected: `All tests passed!`.

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.

```bash
git add entities/skills/scenes/blockade.gd entities/skills/remove_walls_skill.gd tests/test_blockade.gd tests/test_remove_walls_skill.gd
git commit -m "Let Remove Walls destroy a Blockade outright"
```

---

### Task 4: Full-suite verification and manual smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full automated test suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20`
Expected: `All tests passed!`.

- [ ] **Step 2: Import and boot smoke test**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"` — expect no new errors.

- [ ] **Step 3: Manual verification in a running Godot session**

Launch the game normally (not headless), cycle to Weaver (Blockade's class), and confirm by hand:
- Triggering Blockade facing an open tile places it one tile ahead — you are never trapped inside it.
- Triggering it facing the enemy spider does nothing — no blockade appears, no cost is spent.
- Triggering it facing a larva kills the larva and the blockade still appears in that square.
- Toggle to the ceiling plane and confirm you can no longer cross a placed Blockade's tile.
- Use Remove Walls on a placed Blockade and confirm it's destroyed in one use; use it on a real wall elsewhere and confirm wall-carving still works as before.

- [ ] **Step 4: Final commit (only if manual verification above required fixes)**

If Step 3 surfaced no issues, there's nothing to commit here. If it did, fix, re-run Steps 1-2, then:

```bash
git add -A
git commit -m "Fix issues found in manual Blockade verification"
```
