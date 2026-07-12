# Ceiling/Plane Mechanics Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `Enemy` real ceiling-plane access gated to active pursuit, make combat and tile-stacking plane-aware everywhere (same-plane-only), replace the ceiling sprite tint with a floor re-color + entity dimming, and add a knockdown-plus-fall-damage penalty for taking a hit while on the ceiling.

**Architecture:** `PlaneComponent` becomes the shared plane authority via two static helpers (`effective_plane`/`same_plane`, defaulting anything without a `PlaneComponent` to `GROUND`) plus a new `apply_hit_fall()` method. `Hurtbox.receive_hit()` — the single existing choke point for every attack — gates on plane and calls into the fall mechanic. `GridMover.spider_tile_contested()` gets the same plane gate for tile-stacking. `Enemy` gains its own `PlaneComponent` and mirrors `Player`'s existing ceiling-blocking branch, plus new AI logic that climbs only while actively chasing a target on the ceiling and settles back to ground otherwise. `MazeRenderer` gains a second floor color keyed to the player's plane; `Level` drives it and reuses the already-shipped `OutlineFx.set_body_alpha()` uniform to dim whichever of Player/Enemy is off the other's plane. `Player`'s old tint-based `_update_sprite_tint()` ceiling branch is deleted.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-13-ceiling-plane-mechanics-design.md` — read once for full context.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1` (read the full output, not `tail`; drop `-gselect=` for the whole suite).
- Import check after any `.tscn` edit: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- New `.gd`/`.tscn` files generate an untracked `.gd.uid`/`.tscn.uid` sidecar the first time Godot imports/runs them — after each task, run `git status` and stage any stray sidecar files.
- `effective_plane(node)` returns `Level.Layer.GROUND` for any node without a `PlaneComponent` child — this is the fallback that keeps every existing entity (larvae, hatchlings, decoys, traps) behaving exactly as today. Never assume every combat participant has a `PlaneComponent`.
- Only touch the files each task's **Files** section lists. This slice touches: `components/plane_component.gd`, `components/hurtbox.gd`, `components/grid_mover.gd`, `entities/enemy/enemy.gd`, `entities/enemy/enemy.tscn`, `entities/player/player.gd`, `world/maze/maze_renderer.gd`, `world/level.gd`, and their tests. No other system.

---

### Task 1: `PlaneComponent` — `effective_plane`/`same_plane` static helpers, `fall_damage` + `apply_hit_fall()`

**Files:**
- Modify: `components/plane_component.gd`
- Test: `tests/test_plane_component.gd` (new)

**Interfaces:**
- Produces: `PlaneComponent.effective_plane(node: Node) -> Level.Layer` (static), `PlaneComponent.same_plane(a: Node, b: Node) -> bool` (static), `PlaneComponent.fall_damage: float` (`@export`, default `8.0`), `PlaneComponent.apply_hit_fall(health: HealthComponent) -> void` — consumed by Task 2.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_plane_component.gd`:

```gdscript
extends GutTest
## PlaneComponent's shared static helpers (ceiling/plane mechanics rework):
## effective_plane()/same_plane() default anything without a PlaneComponent
## to GROUND, and apply_hit_fall() is the knockdown-plus-fall-damage penalty
## for getting hit while on the ceiling.

func _make_owner_with_plane(plane: Level.Layer = Level.Layer.GROUND) -> Node2D:
	var owner := Node2D.new()
	add_child_autofree(owner)
	var plane_comp := PlaneComponent.new()
	owner.add_child(plane_comp)
	plane_comp.current_plane = plane
	return owner


func test_effective_plane_defaults_to_ground_without_a_plane_component() -> void:
	var owner := Node2D.new()
	add_child_autofree(owner)

	assert_eq(PlaneComponent.effective_plane(owner), Level.Layer.GROUND)


func test_effective_plane_defaults_to_ground_for_null() -> void:
	assert_eq(PlaneComponent.effective_plane(null), Level.Layer.GROUND)


func test_effective_plane_reads_the_plane_component_when_present() -> void:
	var owner := _make_owner_with_plane(Level.Layer.CEILING)

	assert_eq(PlaneComponent.effective_plane(owner), Level.Layer.CEILING)


func test_same_plane_true_when_both_ground_by_default() -> void:
	var a := Node2D.new()
	var b := Node2D.new()
	add_child_autofree(a)
	add_child_autofree(b)

	assert_true(PlaneComponent.same_plane(a, b))


func test_same_plane_false_when_planes_differ() -> void:
	var a := _make_owner_with_plane(Level.Layer.GROUND)
	var b := _make_owner_with_plane(Level.Layer.CEILING)

	assert_false(PlaneComponent.same_plane(a, b))


func test_apply_hit_fall_transitions_to_ground_and_deals_fall_damage_from_ceiling() -> void:
	var plane_comp := PlaneComponent.new()
	add_child_autofree(plane_comp)
	plane_comp.current_plane = Level.Layer.CEILING
	plane_comp.fall_damage = 8.0
	var health := HealthComponent.new()
	health.max_health = 100.0
	add_child_autofree(health)
	health.current_health = 50.0

	plane_comp.apply_hit_fall(health)

	assert_eq(plane_comp.current_plane, Level.Layer.GROUND, "knocked down to the ground")
	assert_almost_eq(health.current_health, 42.0, 0.001, "eats the bonus fall-damage tick")


func test_apply_hit_fall_is_a_noop_while_already_on_the_ground() -> void:
	var plane_comp := PlaneComponent.new()
	add_child_autofree(plane_comp)
	plane_comp.current_plane = Level.Layer.GROUND
	var health := HealthComponent.new()
	health.max_health = 100.0
	add_child_autofree(health)
	health.current_health = 50.0

	plane_comp.apply_hit_fall(health)

	assert_eq(plane_comp.current_plane, Level.Layer.GROUND)
	assert_almost_eq(health.current_health, 50.0, 0.001, "no extra damage from the ground")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_plane_component.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'effective_plane'` (and `same_plane`, `apply_hit_fall`).

- [ ] **Step 3: Write the implementation**

Replace the whole of `components/plane_component.gd` with:

```gdscript
class_name PlaneComponent
extends Node
## Tracks which physical plane (ground/ceiling) the owner currently occupies
## (design §1: Dual-Plane Map Architecture). Player.gd wires its GridMover's
## block_check through `blocked(tile, dir)` here while on the ceiling (ground
## stepping keeps its existing test_move-based check unchanged — see
## Player._blocked). `level` is normally assigned directly by whoever binds
## the level (Player.bind_level, mirroring Enemy.bind_level); `level_path` is
## a fallback for a scene that wants to wire it by NodePath instead.
##
## Ceiling/plane mechanics rework: also the shared plane authority for combat
## and tile-stacking (effective_plane()/same_plane()), and owns the
## knockdown-plus-fall-damage penalty for getting hit while on the ceiling
## (apply_hit_fall()) — kept here rather than on Hurtbox so any future
## plane-aware entity gets consistent fall behavior automatically.

signal plane_changed(plane: Level.Layer)

@export var level_path: NodePath
## First-pass balance number — tune during playtest.
@export var fall_damage: float = 8.0

var level: Level
var current_plane: Level.Layer = Level.Layer.GROUND


func _ready() -> void:
	if level == null and not level_path.is_empty():
		level = get_node_or_null(level_path) as Level


func transition() -> void:
	current_plane = Level.Layer.CEILING if current_plane == Level.Layer.GROUND else Level.Layer.GROUND
	plane_changed.emit(current_plane)
	EventBus.plane_changed.emit(get_parent(), current_plane)


## Blocking seam: whether stepping from `tile` in `dir` is blocked on
## whichever plane this owner currently occupies.
func blocked(tile: Vector2i, dir: Vector2i) -> bool:
	if level == null:
		return false
	return level.is_blocked(tile + dir, current_plane)


## A node's plane if it has a PlaneComponent child, else GROUND — the
## default for every entity that never tracks planes at all (larvae,
## decoys, hatchlings, traps, Blockade).
static func effective_plane(node: Node) -> Level.Layer:
	if node == null:
		return Level.Layer.GROUND
	var plane := node.get_node_or_null("PlaneComponent") as PlaneComponent
	return plane.current_plane if plane != null else Level.Layer.GROUND


static func same_plane(a: Node, b: Node) -> bool:
	return effective_plane(a) == effective_plane(b)


## Called by Hurtbox after a hit lands: knocks the owner down to the ground
## plane and applies bonus fall damage. No-op while already on the ground.
func apply_hit_fall(health: HealthComponent) -> void:
	if current_plane != Level.Layer.CEILING:
		return
	transition()
	if health != null:
		health.take_damage(fall_damage)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_plane_component.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add components/plane_component.gd tests/test_plane_component.gd
git status # stage a stray .gd.uid if one appears
git commit -m "PlaneComponent: effective_plane/same_plane helpers, fall-on-hit penalty"
```

---

### Task 2: `Hurtbox` — same-plane-only combat gate + fall-on-hit wiring

**Files:**
- Modify: `components/hurtbox.gd`
- Test: `tests/test_hurtbox.gd` (extend)

**Interfaces:**
- Consumes: `PlaneComponent.same_plane()`, `PlaneComponent.apply_hit_fall()` (Task 1).
- Produces: `Hurtbox.receive_hit()` rejects cross-plane hits outright and triggers the victim's fall-on-hit penalty when applicable.

- [ ] **Step 1: Write the failing tests**

`tests/test_hurtbox.gd` already has `_make_hurtbox_with_health(health_value: float) -> Array` (returns `[hurtbox, health]`, wired via `health_path = NodePath("../HealthComponent")` on a shared `owner` `Node2D`). Append, reusing it exactly and attaching `PlaneComponent`s to each test's `owner` (the victim) and a separate `attacker` node:

```gdscript
func test_receive_hit_is_a_noop_when_attacker_and_victim_are_on_different_planes() -> void:
	var pair := _make_hurtbox_with_health(100.0)
	var hurtbox: Hurtbox = pair[0]
	var health: HealthComponent = pair[1]
	# PlaneComponent.new() must be explicitly named — a runtime-created node
	# isn't auto-named after its class_name (that only happens for nodes
	# placed in a .tscn), and effective_plane() looks it up as
	# "PlaneComponent" by name, exactly like player.tscn/enemy.tscn wire it.
	var victim_plane := PlaneComponent.new()
	victim_plane.name = "PlaneComponent"
	hurtbox.get_parent().add_child(victim_plane)
	victim_plane.current_plane = Level.Layer.GROUND
	var attacker := Node2D.new()
	add_child_autofree(attacker)
	var attacker_plane := PlaneComponent.new()
	attacker_plane.name = "PlaneComponent"
	attacker.add_child(attacker_plane)
	attacker_plane.current_plane = Level.Layer.CEILING

	hurtbox.receive_hit(10.0, attacker)

	assert_almost_eq(health.current_health, 100.0, 0.001, "a cross-plane hit never lands")


func test_receive_hit_lands_normally_when_both_default_to_ground() -> void:
	var pair := _make_hurtbox_with_health(100.0)
	var hurtbox: Hurtbox = pair[0]
	var health: HealthComponent = pair[1]
	var attacker := Node2D.new()
	add_child_autofree(attacker)

	hurtbox.receive_hit(10.0, attacker)

	assert_almost_eq(health.current_health, 90.0, 0.001, "neither side has a PlaneComponent, so both default to GROUND")


func test_receive_hit_knocks_a_ceiling_victim_down_and_applies_fall_damage() -> void:
	var pair := _make_hurtbox_with_health(100.0)
	var hurtbox: Hurtbox = pair[0]
	var health: HealthComponent = pair[1]
	var victim_plane := PlaneComponent.new()
	victim_plane.name = "PlaneComponent"
	hurtbox.get_parent().add_child(victim_plane)
	victim_plane.current_plane = Level.Layer.CEILING
	victim_plane.fall_damage = 8.0
	var attacker := Node2D.new()
	add_child_autofree(attacker)
	var attacker_plane := PlaneComponent.new()
	attacker_plane.name = "PlaneComponent"
	attacker.add_child(attacker_plane)
	attacker_plane.current_plane = Level.Layer.CEILING # same plane, so the hit lands

	hurtbox.receive_hit(10.0, attacker)

	assert_eq(victim_plane.current_plane, Level.Layer.GROUND, "knocked down by the hit")
	assert_almost_eq(health.current_health, 82.0, 0.001, "10 damage from the hit, 8 more from the fall")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_hurtbox.gd 2>&1`
Expected: FAIL — `test_receive_hit_is_a_noop_when_attacker_and_victim_are_on_different_planes` fails (today's `receive_hit()` has no plane check, so the hit lands and health drops to 90); `test_receive_hit_knocks_a_ceiling_victim_down_and_applies_fall_damage` fails (no fall damage applied, plane never transitions).

- [ ] **Step 3: Write the implementation**

Replace the whole of `components/hurtbox.gd` with:

```gdscript
class_name Hurtbox
extends Area2D
## An entity's damageable area. Forwards hits to its HealthComponent.
## Web shots (and future contact hitboxes) look for a Hurtbox to damage.
##
## health_path is resolved in _ready() rather than exported as a direct
## HealthComponent reference: a hand-written NodePath value in a .tscn does
## not auto-resolve into a Node-typed @export (it silently stays null), which
## is exactly what left melee/web-shot damage a no-op on both spiders.
##
## Every existing attack (melee, web shot) resolves through receive_hit(), so
## it's also the single choke point for the Camouflage guardrail: an attack
## registering here breaks Camouflage on both the victim (this Hurtbox's
## owner) and the attacker (`source`), if either has it active.
##
## Ceiling/plane mechanics rework: also the single choke point for
## same-plane-only combat (an attack from a different plane never lands at
## all — no damage, no signal, no Camouflage break) and the
## knockdown-plus-fall-damage penalty for a victim currently on the ceiling.

@export var health_path: NodePath
var health: HealthComponent

signal took_hit(amount: float, source: Node)


func _ready() -> void:
	if health == null and not health_path.is_empty():
		health = get_node_or_null(health_path) as HealthComponent


func receive_hit(amount: float, source: Node = null) -> void:
	if not PlaneComponent.same_plane(get_parent(), source):
		return
	took_hit.emit(amount, source)
	CamouflageSkill.break_if_present(get_parent())
	CamouflageSkill.break_if_present(source)
	if health != null:
		health.take_damage(amount)
		var plane := get_parent().get_node_or_null("PlaneComponent") as PlaneComponent
		if plane != null:
			plane.apply_hit_fall(health)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_hurtbox.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add components/hurtbox.gd tests/test_hurtbox.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Hurtbox: same-plane-only combat gate + fall-on-hit penalty"
```

---

### Task 3: `GridMover` — same-plane-only tile stacking

**Files:**
- Modify: `components/grid_mover.gd`
- Test: `tests/test_grid_mover.gd` (extend)

**Interfaces:**
- Consumes: `PlaneComponent.same_plane()` (Task 1).
- Produces: `GridMover.spider_tile_contested()` only contests a tile against a node on the same plane.

- [ ] **Step 1: Write the failing test**

`tests/test_grid_mover.gd` already has a `_make_spider(pos: Vector2) -> Array` helper (returns `[node, mover]`, node in group `"spiders"`) used by the existing `test_spider_tile_contested_*` tests. Append, reusing it exactly the same way `test_spider_tile_contested_blocks_a_step_into_an_in_flight_destination` does:

```gdscript
func test_spider_tile_contested_ignores_a_node_on_a_different_plane() -> void:
	var enemy_pair := _make_spider(Vector2(288, 240)) # tile (6,5)
	var enemy_mover: GridMover = enemy_pair[1]
	var enemy_node: Node2D = enemy_pair[0]
	var enemy_plane := PlaneComponent.new()
	enemy_plane.name = "PlaneComponent" # runtime nodes aren't auto-named after class_name
	enemy_node.add_child(enemy_plane)
	enemy_plane.current_plane = Level.Layer.CEILING # the "other" spider is on the ceiling
	var player_pair := _make_spider(Vector2(192, 240)) # tile (4,5), stays GROUND (no PlaneComponent)
	var player_mover: GridMover = player_pair[1]

	assert_true(enemy_mover.try_step(Vector2i.LEFT), "starts clear, toward the empty tile (5,5)")
	enemy_mover.tick(0.03) # partway through the step, not yet landed

	assert_false(GridMover.spider_tile_contested(player_mover, player_pair[0], Vector2i.RIGHT),
		"the enemy committed to (5,5), but it's on a different plane — never contests")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_grid_mover.gd 2>&1`
Expected: FAIL — `test_spider_tile_contested_ignores_a_node_on_a_different_plane` fails (today's `spider_tile_contested` contests regardless of plane, so it returns `true`).

- [ ] **Step 3: Write the implementation**

In `components/grid_mover.gd`, replace `spider_tile_contested()`:

```gdscript
## True if stepping `dir` from `self_node` would land on a tile another spider
## already owns — occupied now, or already committed to via an in-flight step.
## Shared by Player and Enemy so spiders can't land on each other's tile.
## Ceiling/plane mechanics rework: only contests against a node on the same
## plane — a ground spider and a ceiling spider physically occupy different
## layers and never block each other's tile.
static func spider_tile_contested(mover: GridMover, self_node: Node2D, dir: Vector2i) -> bool:
	var target_pos := self_node.global_position + Vector2(dir) * float(mover.tile_size)
	var ts := float(mover.tile_size)
	var target_tile := Vector2i(int(floorf(target_pos.x / ts)), int(floorf(target_pos.y / ts)))
	for node in self_node.get_tree().get_nodes_in_group("spiders"):
		if node == self_node:
			continue
		var other := node as Node2D
		if other == null or not PlaneComponent.same_plane(self_node, other):
			continue
		var other_mover := other.get_node_or_null("GridMover") as GridMover
		if other_mover != null and other_mover.committed_tile() == target_tile:
			return true
	return false
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_grid_mover.gd 2>&1`
Expected: `All tests passed!` (existing same-plane tests stay green — neither node in them has a `PlaneComponent`, so both default to `GROUND` and still contest each other exactly as before).

- [ ] **Step 5: Commit**

```bash
git add components/grid_mover.gd tests/test_grid_mover.gd
git status # stage a stray .gd.uid if one appears
git commit -m "GridMover: same-plane-only tile stacking"
```

---

### Task 4: `Enemy` — `PlaneComponent` wiring + ceiling-aware blocking

**Files:**
- Modify: `entities/enemy/enemy.tscn`
- Modify: `entities/enemy/enemy.gd`
- Test: `tests/test_enemy_ai.gd` (extend)

**Interfaces:**
- Consumes: `PlaneComponent` (Task 1), `Level.is_blocked(tile, plane)` (existing, unmodified).
- Produces: `Enemy._plane: PlaneComponent` (`@onready`), `Enemy._blocked()` branches by plane the same way `Player._blocked()` already does. Task 5 consumes `Enemy._plane`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_enemy_ai.gd`:

```gdscript
func test_enemy_has_a_plane_component_defaulting_to_ground() -> void:
	var enemy := _make_enemy() # use this file's existing enemy-construction helper
	var plane := enemy.get_node_or_null("PlaneComponent") as PlaneComponent

	assert_not_null(plane, "Enemy gains a PlaneComponent (ceiling/plane mechanics rework)")
	assert_eq(plane.current_plane, Level.Layer.GROUND)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_ai.gd 2>&1`
Expected: FAIL — `assert_not_null` fails, no `PlaneComponent` child exists yet.

- [ ] **Step 3: Write the implementation**

In `entities/enemy/enemy.tscn`, add a new `ext_resource` for the script (after the existing `id="12_inventory"` line):

```
[ext_resource type="Script" path="res://components/plane_component.gd" id="13_plane"]
```

And add a new node after the `[node name="InventoryComponent" ...]` block (at the end of the file):

```
[node name="PlaneComponent" type="Node" parent="."]
script = ExtResource("13_plane")
```

In `entities/enemy/enemy.gd`, add the `@onready` var alongside the existing ones:

```gdscript
@onready var _plane: PlaneComponent = $PlaneComponent
```

In `bind_level()`, wire the level reference the same way `Player.bind_level()` already does:

```gdscript
## Level calls this right after instancing so the enemy can path on the grid.
func bind_level(level: Node) -> void:
	_level = level
	_plane.level = level
```

Replace `_blocked()`:

```gdscript
## Blocking seam for the GridMover: checks a tile the player has already
## committed to (mid-step, not just physically standing on) before falling
## back to the body's own physics (walls, traps, a stationary spider).
## Ceiling/plane mechanics rework: mirrors Player._blocked()'s plane branch —
## on the ceiling, blocking is decided entirely by Level.is_blocked (no
## separate physical collider up there); on the ground, is_blocked() adds
## the pit check on top of the existing test_move physics check.
func _blocked(dir: Vector2i) -> bool:
	if GridMover.spider_tile_contested(_mover, self, dir):
		return true
	if _level != null:
		var target := _level.tile_of(global_position) + dir
		if _plane.current_plane == Level.Layer.CEILING:
			return _level.is_blocked(target, Level.Layer.CEILING)
		if _level.is_blocked(target, Level.Layer.GROUND):
			return true
	return test_move(global_transform, Vector2(dir) * float(_mover.tile_size))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_ai.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Run the full suite once** (this task changes a shared scene file — a good point to catch any other test that instantiates `EnemyScene` and asserts on its exact child count/structure)

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!` If something else broke, fix it as part of this task before committing — don't defer a scene-wiring regression to a later task.

- [ ] **Step 7: Commit**

```bash
git add entities/enemy/enemy.tscn entities/enemy/enemy.gd tests/test_enemy_ai.gd
git status # stage a stray .tscn.uid if one appears
git commit -m "Enemy: PlaneComponent wiring + ceiling-aware blocking"
```

---

### Task 5: `Enemy` AI — climb only while actively chasing, settle back to ground otherwise

**Files:**
- Modify: `entities/enemy/enemy.gd`
- Test: `tests/test_enemy_ai.gd` (extend)

**Interfaces:**
- Consumes: `Enemy._plane` (Task 4), `PlaneComponent.effective_plane()` (Task 1).
- Produces: `Enemy._match_plane_to(target: Node2D) -> void`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_enemy_ai.gd`:

```gdscript
func test_enemy_climbs_to_match_a_target_on_the_ceiling_while_entering_chase() -> void:
	var enemy := _make_enemy()
	var target := Node2D.new()
	add_child_autofree(target)
	target.add_to_group("player")
	var target_plane := PlaneComponent.new()
	target_plane.name = "PlaneComponent" # runtime nodes aren't auto-named after class_name
	target.add_child(target_plane)
	target_plane.current_plane = Level.Layer.CEILING
	enemy._current_target = target

	enemy._match_plane_to(target)

	assert_eq(enemy._plane.current_plane, Level.Layer.CEILING)


func test_enemy_never_climbs_to_chase_a_plane_less_target() -> void:
	var enemy := _make_enemy()
	var decoy := Node2D.new() # no PlaneComponent -> always effective_plane() == GROUND
	add_child_autofree(decoy)

	enemy._match_plane_to(decoy)

	assert_eq(enemy._plane.current_plane, Level.Layer.GROUND)


func test_enemy_settles_back_to_ground_when_state_leaves_chase() -> void:
	var enemy := _make_enemy()
	enemy._plane.current_plane = Level.Layer.CEILING
	enemy.state = Enemy.State.PATROL
	enemy._current_target = null

	enemy._update_state()

	assert_eq(enemy._plane.current_plane, Level.Layer.GROUND, "not chasing anymore, so it climbs back down")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_ai.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function '_match_plane_to'`; the settle-back test may pass trivially or fail depending on the current `_update_state()` body — verify it actually exercises new behavior once Step 3 lands (if `state` never actually changes because `_update_state()`'s own next-state computation leaves it at `PATROL`, that's expected here — the test's point is the plane transition, not the state itself).

- [ ] **Step 3: Write the implementation**

In `entities/enemy/enemy.gd`, find `_update_state()`'s closing block:

```gdscript
	if next != state:
		state = next
		_repath_left = 0.0
		_path = []
		if next == State.PATROL or next == State.SEEK_FOOD:
			_state_lock_left = state_min_duration
```

Add plane handling right after it, still inside `_update_state()`:

```gdscript
	if next == State.CHASE and _current_target != null:
		_match_plane_to(_current_target)
	elif _plane.current_plane == Level.Layer.CEILING:
		_plane.transition() # settle back to ground: not actively chasing anymore
```

Add the new method near `_do_chase()`:

```gdscript
## Ceiling/plane mechanics rework: the enemy only ever climbs to match a
## target's plane while actively chasing it (called from _update_state()),
## and always settles back to ground the instant it isn't chasing (see the
## call site above) — the minimum that makes same-plane combat meaningful.
## A target with no PlaneComponent (a Decoy) is always effective_plane()
## GROUND, so the enemy never climbs to "chase" a decoy prop. Instant
## transition, matching the existing Player.toggle_plane precedent exactly —
## no climb-reaction delay (design's explicit out-of-scope call).
func _match_plane_to(target: Node2D) -> void:
	if PlaneComponent.effective_plane(target) != _plane.current_plane:
		_plane.transition()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_enemy_ai.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Run the full suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!` (this touches `_update_state()`, which every other Enemy state test also exercises — confirm nothing regressed).

- [ ] **Step 6: Commit**

```bash
git add entities/enemy/enemy.gd tests/test_enemy_ai.gd
git commit -m "Enemy: climb to match a chased target's plane, settle back to ground otherwise"
```

---

### Task 6: `MazeRenderer` — per-plane floor color, driven by the player's plane

**Files:**
- Modify: `world/maze/maze_renderer.gd`
- Modify: `world/level.gd`
- Test: `tests/test_maze_renderer_plane.gd` (new)

**Interfaces:**
- Produces: `MazeRenderer.set_active_plane(plane: Level.Layer) -> void`, `MazeRenderer.ceiling_floor_color: Color`. Consumed by `Level` in this task, and indirectly by Task 7 (which drives entity dimming off the same `EventBus.plane_changed` event this task subscribes to).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_maze_renderer_plane.gd`:

```gdscript
extends GutTest
## MazeRenderer's per-plane floor color (ceiling/plane mechanics rework):
## replaces the old ceiling sprite tint with a floor re-color, so the ground
## renders in floor_color and the ceiling in ceiling_floor_color — the
## roadmap's literal "floor re-colors (not spider)" requirement.

func _make_renderer() -> MazeRenderer:
	var renderer := MazeRenderer.new()
	add_child_autofree(renderer)
	var maze := MazeGenerator.generate(3, 3, 1)
	renderer.setup(maze, 48)
	return renderer


func test_defaults_to_ground_floor_color() -> void:
	var renderer := _make_renderer()

	assert_eq(renderer._active_plane, Level.Layer.GROUND)


func test_set_active_plane_to_ceiling_switches_the_tracked_plane() -> void:
	var renderer := _make_renderer()

	renderer.set_active_plane(Level.Layer.CEILING)

	assert_eq(renderer._active_plane, Level.Layer.CEILING)


func test_set_active_plane_back_to_ground_switches_back() -> void:
	var renderer := _make_renderer()
	renderer.set_active_plane(Level.Layer.CEILING)

	renderer.set_active_plane(Level.Layer.GROUND)

	assert_eq(renderer._active_plane, Level.Layer.GROUND)


func test_floor_and_ceiling_colors_are_distinct() -> void:
	var renderer := _make_renderer()

	assert_ne(renderer.floor_color, renderer.ceiling_floor_color)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_maze_renderer_plane.gd 2>&1`
Expected: FAIL — `Invalid get index '_active_plane'` / `Invalid call. Nonexistent function 'set_active_plane'` / `Invalid get index 'ceiling_floor_color'`.

- [ ] **Step 3: Write the implementation**

Replace the whole of `world/maze/maze_renderer.gd` with:

```gdscript
class_name MazeRenderer
extends Node2D
## Draws a MazeData as flat floor/wall rectangles. A placeholder for the
## SpriteCook TileSet: once tile art exists this can be swapped for a
## TileMapLayer without touching the rest of the maze pipeline (collision,
## occluders and navigation are built separately by Level).
##
## Ceiling/plane mechanics rework: open tiles render in floor_color or
## ceiling_floor_color depending on which plane the player currently
## occupies (set_active_plane(), driven by Level) — replaces the old
## per-sprite ceiling tint entirely. Wall color is unchanged on both planes:
## walls exist identically on both layers (CeilingData mirrors MazeData's
## wall geometry 1:1), so there's nothing distinct to show there.

var _maze: MazeData
var _tile_size := 48
var floor_color := Color(0.17, 0.15, 0.13)
var ceiling_floor_color := Color(0.13, 0.17, 0.24)
var wall_color := Color(0.31, 0.27, 0.23)
## Grid lines on top of open floor tiles, so the tile-stepped movement reads
## clearly against the map.
var grid_line_color := Color(1, 1, 1, 0.08)

var _active_plane: Level.Layer = Level.Layer.GROUND


func setup(maze: MazeData, tile_size: int) -> void:
	_maze = maze
	_tile_size = tile_size
	queue_redraw()


## Which plane's floor color open tiles should currently draw in — the
## player's own plane (there's one camera, one local viewer).
func set_active_plane(plane: Level.Layer) -> void:
	_active_plane = plane
	queue_redraw()


func _draw() -> void:
	if _maze == null:
		return
	var open_color := floor_color if _active_plane == Level.Layer.GROUND else ceiling_floor_color
	for y in _maze.height:
		for x in _maze.width:
			var rect := Rect2(x * _tile_size, y * _tile_size, _tile_size, _tile_size)
			draw_rect(rect, open_color if _maze.is_open(x, y) else wall_color)
	_draw_grid_lines()


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

In `world/level.gd`, add to `_ready()`:

```gdscript
func _ready() -> void:
	# Lets skills/hazards find "the current level" generically (e.g.
	# RemoveWallsSkill, BlockadeSkill) without needing it threaded through
	# every call site the way Enemy.bind_level() does.
	add_to_group("level")
	# Ceiling/plane mechanics rework: floor re-color tracks the player's own
	# plane; entity dimming (Task 7) reacts to anyone's plane change.
	EventBus.plane_changed.connect(_on_plane_changed)
```

Add the new handler near `_spawn_entities()`:

```gdscript
## Ceiling/plane mechanics rework: the rendered floor always reflects the
## player's own plane specifically (one camera, one local viewer) — an
## enemy transitioning doesn't touch the floor color at all.
func _on_plane_changed(who: Node, _plane: int) -> void:
	if who == player:
		_renderer.set_active_plane(player.get_node("PlaneComponent").current_plane)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_maze_renderer_plane.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add world/maze/maze_renderer.gd world/level.gd tests/test_maze_renderer_plane.gd
git status # stage a stray .gd.uid if one appears
git commit -m "MazeRenderer: per-plane floor color, driven by the player's plane"
```

---

### Task 7: Entity dimming (`body_alpha`) + delete the old sprite-tint ceiling cue

**Files:**
- Modify: `world/level.gd`
- Modify: `entities/player/player.gd`
- Test: `tests/test_level_plane_focus.gd` (new)
- Test: `grep -rn "_update_sprite_tint\|0.55, 0.65, 0.85" tests/` first — fix any test asserting the old ceiling tint

**Interfaces:**
- Consumes: `OutlineFx.set_body_alpha()` (existing, shipped in the Hatchlings/VFX round), `PlaneComponent.effective_plane()` (Task 1), `EventBus.plane_changed` (existing signal, now also consumed by Task 6's handler in the same `_ready()`).
- Produces: `Level._refresh_plane_focus() -> void` (private, called from `_on_plane_changed()`).

- [ ] **Step 1: Search for the existing sprite-tint test to remove/replace**

Run: `grep -rn "_update_sprite_tint\|ceiling.*tint\|0.55, 0.65, 0.85" tests/`

Delete or rewrite whatever test currently asserts the player's sprite `modulate` changes to the cool-tinted color on the ceiling — that behavior is being removed in this task. If the only coverage is indirect (e.g. via `apply_class`), no test file needs touching for the deletion itself; just confirm with the grep above before proceeding.

- [ ] **Step 2: Write the failing tests**

Create `tests/test_level_plane_focus.gd`, reusing the exact same `_make_level()` helper pattern `tests/test_level_sense_and_pits.gd` already uses (instantiate `res://world/level.tscn`, call `.build()`):

```gdscript
extends GutTest
## Level's plane-focus dimming (ceiling/plane mechanics rework): whichever of
## Player/Enemy is off the other's plane dims via the shared outline
## shader's body_alpha uniform (already shipped for Camouflage) — the floor
## re-color tells you which plane you're on, this tells you which other
## spider is or isn't reachable from here.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_refresh_plane_focus_dims_the_enemy_when_only_it_is_on_the_ceiling() -> void:
	var level := _make_level()
	var enemy_plane := level.enemy.get_node("PlaneComponent") as PlaneComponent
	enemy_plane.current_plane = Level.Layer.CEILING

	level._refresh_plane_focus()

	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	var mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), 0.35, 0.001,
		"enemy is off the player's plane, so it dims")


func test_refresh_plane_focus_keeps_full_brightness_when_planes_match() -> void:
	var level := _make_level()

	level._refresh_plane_focus() # both default GROUND

	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	var mat := enemy_sprite.material as ShaderMaterial
	if mat != null: # no material yet is equally valid — body_alpha defaults to 1.0
		assert_almost_eq(mat.get_shader_parameter("body_alpha"), 1.0, 0.001)


func test_plane_changed_event_triggers_a_focus_refresh() -> void:
	var level := _make_level()
	var enemy_plane := level.enemy.get_node("PlaneComponent") as PlaneComponent

	enemy_plane.transition() # fires EventBus.plane_changed(enemy, CEILING)

	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem
	var mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), 0.35, 0.001)


## Camouflage conflict guardrail (design's explicit judgment call): body_alpha
## is not ref-counted, so plane-focus dimming must never clobber an active
## Camouflage's near-invisible body.
func test_refresh_plane_focus_never_touches_a_camouflaged_players_body_alpha() -> void:
	var level := _make_level()
	var camo := level.player.get_node("CamouflageSkill") as CamouflageSkill
	if camo == null:
		pending("current active class has no CamouflageSkill — not exercised this run")
		return
	camo.activate(level.player)
	var player_sprite := level.player.get_node("Sprite") as CanvasItem
	var camo_alpha: float = (player_sprite.material as ShaderMaterial).get_shader_parameter("body_alpha")
	var enemy_plane := level.enemy.get_node("PlaneComponent") as PlaneComponent

	enemy_plane.transition() # triggers a _refresh_plane_focus() via the plane_changed event

	var mat := player_sprite.material as ShaderMaterial
	assert_almost_eq(mat.get_shader_parameter("body_alpha"), camo_alpha, 0.001,
		"plane-focus dimming must not overwrite Camouflage's own body_alpha")
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_plane_focus.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function '_refresh_plane_focus'`.

- [ ] **Step 4: Write the implementation**

In `world/level.gd`, add a constant near `SENSE_OUTLINE_COLOR`:

```gdscript
## Ceiling/plane mechanics rework: body_alpha for whichever of Player/Enemy
## is off the other's plane — "less in focus," per the user's own framing
## during brainstorming. Deliberately scoped to just these two (the only
## entities that track a plane at all); larvae/hatchlings/decoys/traps
## always render at full brightness regardless of plane (design's explicit
## out-of-scope call).
const OFF_PLANE_ALPHA := 0.35
```

Replace `_on_plane_changed()` (added in Task 6) with:

```gdscript
## Ceiling/plane mechanics rework: the rendered floor always reflects the
## player's own plane specifically (one camera, one local viewer) — an
## enemy transitioning doesn't touch the floor color. Either side changing
## plane can change their *relative* same/different-plane relationship
## though, so both trigger a full dimming refresh.
func _on_plane_changed(who: Node, _plane: int) -> void:
	if who == player:
		_renderer.set_active_plane(player.get_node("PlaneComponent").current_plane)
	_refresh_plane_focus()


## Dims whichever of Player/Enemy is off the other's plane via the shared
## outline shader's body_alpha uniform (already shipped for Camouflage) —
## the floor re-color (above) tells you which plane *you're* on; this tells
## you which other spider is or isn't reachable from here.
##
## Camouflage guardrail: body_alpha isn't reference-counted (last caller
## wins, by design — see OutlineFx.set_body_alpha's own doc comment), so a
## node with an active CamouflageSkill is skipped entirely here — Camouflage
## keeps sole control of that node's body_alpha until it breaks.
func _refresh_plane_focus() -> void:
	if player == null or enemy == null:
		return
	var focus_plane := PlaneComponent.effective_plane(player)
	for node in [player, enemy]:
		if not is_instance_valid(node):
			continue
		var camo := node.get_node_or_null("CamouflageSkill") as CamouflageSkill
		if camo != null and camo.active:
			continue
		var vis := node.get_node_or_null("Sprite") as CanvasItem
		if vis == null:
			continue
		var alpha := 1.0 if PlaneComponent.effective_plane(node) == focus_plane else OFF_PLANE_ALPHA
		OutlineFx.set_body_alpha(vis, alpha)
```

In `entities/player/player.gd`, delete `_on_plane_changed()` and `_update_sprite_tint()`'s ceiling branch. Replace:

```gdscript
## Visual cue for which plane the player currently occupies — a dim,
## cool-toned tint on the ceiling, restored to normal on the ground.
func _on_plane_changed(_plane_arg: Level.Layer) -> void:
	_update_sprite_tint()


## The sprite's tint is the active class's color, dimmed/cooled by the
## ceiling tint on top when on the ceiling plane — the two effects compose
## instead of one clobbering the other.
func _update_sprite_tint() -> void:
	var base := _active_class_data.display_color if _active_class_data != null else Color.WHITE
	if _plane.current_plane == Level.Layer.CEILING:
		sprite.modulate = base * Color(0.55, 0.65, 0.85, 0.85)
	else:
		sprite.modulate = base
```

with:

```gdscript
## The sprite's tint is always just the active class's color now — the
## ceiling/plane mechanics rework replaced the old ceiling tint-multiply
## (which clashed with each class's identity color) with a floor re-color +
## entity dimming instead (see Level._refresh_plane_focus()).
func _update_sprite_tint() -> void:
	sprite.modulate = _active_class_data.display_color if _active_class_data != null else Color.WHITE
```

Search for wherever `_plane.plane_changed.connect(_on_plane_changed)` (or similar) was wired in `player.gd`'s `_ready()`/scene-setup and remove that connection line — `_update_sprite_tint()` is no longer plane-reactive, it only needs calling from `apply_class()` (already the case) and initial setup.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_plane_focus.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Run the full suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!` — confirm the deleted `_on_plane_changed()`/`_update_sprite_tint()` change in `player.gd` didn't strand any other test that asserted on the old tint.

- [ ] **Step 7: Import check + headless scene boot** (per this repo's Godot validation workflow — memory: godot-validation-workflow)

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add world/level.gd entities/player/player.gd tests/test_level_plane_focus.gd
git status # stage a stray .gd.uid if one appears, and any other test file fixed in Step 1
git commit -m "Level/Player: dim off-plane Player/Enemy via body_alpha, delete the old ceiling sprite tint"
```

---

## Final whole-branch pass (not a numbered task — do this after Task 7)

- Run the full GUT suite once more end-to-end.
- Manual/windowed playtest pass specifically for: floor color actually changes when toggling `toggle_plane` (C); the enemy visibly climbs to the ceiling only while chasing a ceiling player and comes back down once it loses them; a melee/web hit against a different-plane target visibly does nothing; taking a hit while on the ceiling visibly drops the victim to the ground plane. This is exactly the category of thing GUT can't catch (shader uniform values reads as "correct" while looking wrong in real play) per the Hatchlings/VFX round's Sense lesson (memory: burrow-playtest-roadmap) — don't skip it even though every automated test is green.
- Update `docs/superpowers/specs/2026-07-13-ceiling-plane-mechanics-design.md`'s judgment calls are already documented; no further spec edits expected unless the manual pass surfaces something.
