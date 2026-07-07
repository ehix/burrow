# Grid Movement & Web-Combat Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Burrow's slice-1 playfield to full tile-step grid movement and give webs a real identity — damage + slow, larva-killing, and destructible traps — while making the enemy feed itself so it stops passively starving.

**Architecture:** A shared `GridMover` component drives cell-to-cell stepping for player, enemy, and larva (blocking via each body's own `test_move`, so entities stay decoupled from `MazeData`). A `GridNav` helper builds an `AStarGrid2D` from the maze for enemy pathing, replacing the navmesh. Web shots branch by what they hit (hurtbox → damage + slow; larva → kill into an inedible corpse; placed trap → 3-hit destruction). The enemy eats larvae by contact and hungers slower.

**Tech Stack:** Godot 4.7 stable (GDScript only), GUT 9.4.0 for headless unit tests, `AStarGrid2D` for grid pathing.

## Global Constraints

- **Engine:** Godot 4.7 stable at `~/.local/bin/godot`. GDScript only, no C#.
- **Tile size:** `TILE_SIZE = 48` (already a `const` in `world/level.gd`). Maze uses the expanded grid (walls are tiles; odd/odd tiles are cell centres).
- **Collision layers:** world=1, player=2, enemy=4, larva=8, hurtbox=16, trap=32.
- **Movement is 4-directional** (no diagonals; corridors are one tile wide). Diagonal input resolves to its dominant axis.
- **Determinism:** the maze and any pathing on it must stay reproducible for a fixed seed. Larva *wander* may use the global RNG (not part of the seed guarantee).
- **All numeric tuning values below are starting points** — expose them as `@export`/`const`, do not hardcode inline.
- **Run the test suite (all tasks):**
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`
  Isolate one file by appending `-gselect=test_NAME.gd`.
- **Import after adding/renaming files:** `~/.local/bin/godot --headless --path . --import`
- **Boot smoke test:** `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 300 2>&1 | grep -Ei 'error|script error|nav' || echo CLEAN`
- **Commit trailer (every commit):**
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK
  ```
- **`.godot/` stays gitignored; commit `.gd.uid` and `*.import` sidecars.**

---

### Task 1: Vendor the GUT test framework

GUT 9.4.0 is already copied into `addons/gut/` (untracked) and verified: the existing 34 tests pass headlessly, including the `EventBus`-dependent `test_web_trap.gd`, confirming autoloads load under the cmdln runner. This task commits it and adds a tiny config so later tasks have a stable test harness.

**Files:**
- Add (untracked, commit as-is): `addons/gut/**`
- Create: `.gutconfig.json`

**Interfaces:**
- Produces: the test-run command in Global Constraints. No code symbols.

- [ ] **Step 1: Confirm the existing suite passes**

Run:
```
~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20
```
Expected: `---- All tests passed! ----`, `34` tests passing.

- [ ] **Step 2: Add a GUT config for convenience**

Create `.gutconfig.json`:
```json
{
  "dirs": ["res://tests"],
  "prefix": "test_",
  "suffix": ".gd",
  "should_exit": true,
  "log_level": 1
}
```

- [ ] **Step 3: Verify config-driven run works**

Run:
```
~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json 2>&1 | tail -5
```
Expected: `All tests passed!` (same 34).

- [ ] **Step 4: Commit**

```bash
git add addons/gut .gutconfig.json
git commit -m "Vendor GUT 9.4.0 for headless unit tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 2: GridMover component

A reusable node that animates its parent `Node2D` one tile at a time. Pure stepping logic is unit-tested by injecting a `block_check` seam and calling `tick(delta)` directly (no physics frames). Production blocking falls back to the parent body's `test_move`.

**Files:**
- Create: `components/grid_mover.gd`
- Test: `tests/test_grid_mover.gd`

**Interfaces:**
- Produces:
  - `class_name GridMover extends Node`
  - `@export var tile_size: int` (48), `@export var step_time: float` (0.12)
  - `var speed_scale: float` (1.0), `var block_check: Callable` (optional `func(dir: Vector2i) -> bool`)
  - `signal step_finished`
  - `func try_step(dir: Vector2i) -> bool` — starts a step if idle & unblocked; buffers `dir` and returns false if already moving; returns false if blocked.
  - `func is_moving() -> bool`
  - `func tick(delta: float) -> void` — advances the current step (also called from `_process`).
  - `func apply_slow(factor: float, duration: float) -> void` — sets `speed_scale = factor`, restores to 1.0 after `duration`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_grid_mover.gd`:
```gdscript
extends GutTest
## GridMover step animation, blocking seam, buffering and slow.
## Pure: injects block_check and drives tick() manually (no physics frames).


func _make_mover(open := true) -> Array:
	# Returns [parent_node2d, mover]. Parent starts at origin.
	var parent := Node2D.new()
	parent.global_position = Vector2.ZERO
	var mover := GridMover.new()
	mover.tile_size = 48
	mover.step_time = 0.1
	mover.block_check = func(_d: Vector2i) -> bool: return not open
	parent.add_child(mover)
	add_child_autofree(parent)
	mover.set_process(false) # drive tick() manually
	return [parent, mover]


func test_step_moves_exactly_one_tile_over_step_time() -> void:
	var m := _make_mover()
	var parent: Node2D = m[0]
	var mover: GridMover = m[1]
	assert_true(mover.try_step(Vector2i.RIGHT), "clear step starts")
	assert_true(mover.is_moving())
	mover.tick(0.05) # half of step_time
	assert_almost_eq(parent.global_position.x, 24.0, 0.5, "halfway across the tile")
	mover.tick(0.05) # finishes
	assert_almost_eq(parent.global_position.x, 48.0, 0.001, "lands on tile centre")
	assert_false(mover.is_moving())


func test_blocked_step_is_refused() -> void:
	var m := _make_mover(false) # block_check always true
	var mover: GridMover = m[1]
	assert_false(mover.try_step(Vector2i.RIGHT), "blocked step refused")
	assert_false(mover.is_moving())


func test_cannot_start_a_second_step_while_moving() -> void:
	var m := _make_mover()
	var mover: GridMover = m[1]
	mover.try_step(Vector2i.RIGHT)
	assert_false(mover.try_step(Vector2i.DOWN), "second step refused mid-step")


func test_buffered_direction_runs_after_finish() -> void:
	var m := _make_mover()
	var parent: Node2D = m[0]
	var mover: GridMover = m[1]
	mover.try_step(Vector2i.RIGHT)
	mover.try_step(Vector2i.DOWN) # buffered
	mover.tick(0.1) # finish RIGHT -> auto-starts buffered DOWN
	assert_true(mover.is_moving(), "buffered step now running")
	mover.tick(0.1) # finish DOWN
	assert_almost_eq(parent.global_position, Vector2(48, 48), 0.001)


func test_step_finished_signal_emits_once_per_step() -> void:
	var m := _make_mover()
	var mover: GridMover = m[1]
	watch_signals(mover)
	mover.try_step(Vector2i.RIGHT)
	mover.tick(0.1)
	assert_signal_emit_count(mover, "step_finished", 1)


func test_apply_slow_reduces_step_speed() -> void:
	var m := _make_mover()
	var parent: Node2D = m[0]
	var mover: GridMover = m[1]
	mover.apply_slow(0.5, 999.0)
	assert_eq(mover.speed_scale, 0.5)
	mover.try_step(Vector2i.RIGHT)
	mover.tick(0.05) # at half speed this is only a quarter of the way
	assert_almost_eq(parent.global_position.x, 12.0, 0.5, "slowed step advances slower")
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_grid_mover.gd 2>&1 | tail -15`
Expected: FAIL — `GridMover` not found / cannot instance.

- [ ] **Step 3: Write the implementation**

Create `components/grid_mover.gd`:
```gdscript
class_name GridMover
extends Node
## Animates its parent Node2D one grid tile at a time (4-directional). Used by
## the player, enemy and larva so they all step on the maze grid identically.
##
## Blocking is decided by `block_check` if set, else by the parent body's
## `test_move` — so entities never need the MazeData handed to them. Stepping
## maths live in tick(delta) so they can be unit-tested without physics frames.

signal step_finished

@export var tile_size: int = 48
@export var step_time: float = 0.12

## Multiplies step speed (1.0 = normal). The web slow drops this below 1.
var speed_scale: float = 1.0
## Optional `func(dir: Vector2i) -> bool` — return true to block a step. When
## unset, the parent PhysicsBody2D.test_move is used instead.
var block_check: Callable = Callable()

var _moving := false
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _elapsed := 0.0
var _buffered := Vector2i.ZERO


func _ready() -> void:
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	tick(delta)


func _mover_node() -> Node2D:
	return get_parent() as Node2D


func is_moving() -> bool:
	return _moving


## Begin a one-tile step in a cardinal direction. Buffers and returns false if
## already moving; returns false if blocked; true if a step started.
func try_step(dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO:
		return false
	if _moving:
		_buffered = dir
		return false
	if _is_blocked(dir):
		return false
	var node := _mover_node()
	_from = node.global_position
	_to = _from + Vector2(dir) * float(tile_size)
	_elapsed = 0.0
	_moving = true
	return true


func _is_blocked(dir: Vector2i) -> bool:
	if block_check.is_valid():
		return block_check.call(dir)
	var body := get_parent() as PhysicsBody2D
	if body == null:
		return false
	return body.test_move(body.global_transform, Vector2(dir) * float(tile_size))


func tick(delta: float) -> void:
	if not _moving:
		return
	_elapsed += delta * speed_scale
	var t := clampf(_elapsed / step_time, 0.0, 1.0)
	_mover_node().global_position = _from.lerp(_to, t)
	if t >= 1.0:
		_moving = false
		step_finished.emit()
		if _buffered != Vector2i.ZERO:
			var d := _buffered
			_buffered = Vector2i.ZERO
			try_step(d)


## Slow to `factor` of normal speed for `duration` seconds, then restore.
func apply_slow(factor: float, duration: float) -> void:
	speed_scale = factor
	if is_inside_tree():
		get_tree().create_timer(duration).timeout.connect(
			func() -> void: speed_scale = 1.0)
```

- [ ] **Step 4: Run to verify it passes**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_grid_mover.gd 2>&1 | tail -12`
Expected: `6/6 passed`.

- [ ] **Step 5: Import & commit**

```bash
~/.local/bin/godot --headless --path . --import 2>&1 | tail -1
git add components/grid_mover.gd components/grid_mover.gd.uid tests/test_grid_mover.gd tests/test_grid_mover.gd.uid
git commit -m "Add GridMover component for tile-step movement

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 3: GridNav pathfinding helper

A stateless helper that builds an `AStarGrid2D` from a `MazeData` (wall tiles marked solid) and returns tile paths. Extracted from `Level` so it's unit-testable without a scene.

**Files:**
- Create: `world/maze/grid_nav.gd`
- Test: `tests/test_grid_nav.gd`

**Interfaces:**
- Consumes: `MazeData` (from `MazeGenerator.generate`).
- Produces:
  - `class_name GridNav extends RefCounted`
  - `static func build(maze: MazeData, cell_size: int) -> AStarGrid2D`
  - `static func path(astar: AStarGrid2D, from: Vector2i, to: Vector2i) -> Array[Vector2i]` — endpoints inclusive; `[]` if either endpoint is out of bounds or solid.

- [ ] **Step 1: Write the failing test**

Create `tests/test_grid_nav.gd`:
```gdscript
extends GutTest
## GridNav builds an AStarGrid2D from a maze and paths over open tiles only.


func test_path_stays_on_open_tiles() -> void:
	var maze := MazeGenerator.generate(6, 6, 42)
	var astar := GridNav.build(maze, 48)
	var open := maze.open_cells()
	var from: Vector2i = open[0]
	var to: Vector2i = open[open.size() - 1]
	var route := GridNav.path(astar, from, to)
	assert_gt(route.size(), 0, "a route exists between two open cells")
	for tile in route:
		assert_true(maze.is_open(tile.x, tile.y),
			"route tile %s must be open floor" % tile)


func test_path_is_deterministic() -> void:
	var maze := MazeGenerator.generate(6, 6, 7)
	var a := GridNav.build(maze, 48)
	var b := GridNav.build(maze, 48)
	var open := maze.open_cells()
	var r1 := GridNav.path(a, open[0], open[open.size() - 1])
	var r2 := GridNav.path(b, open[0], open[open.size() - 1])
	assert_eq(r1, r2, "same maze yields the same path")


func test_path_to_a_wall_is_empty() -> void:
	var maze := MazeGenerator.generate(6, 6, 7)
	var astar := GridNav.build(maze, 48)
	# (0,0) is always the solid outer border.
	var route := GridNav.path(astar, Vector2i(1, 1), Vector2i(0, 0))
	assert_eq(route.size(), 0, "no path into a solid tile")
```

- [ ] **Step 2: Run to verify it fails**

Run: `... -gselect=test_grid_nav.gd 2>&1 | tail -12`
Expected: FAIL — `GridNav` not found.

- [ ] **Step 3: Write the implementation**

Create `world/maze/grid_nav.gd`:
```gdscript
class_name GridNav
extends RefCounted
## Builds an AStarGrid2D from a MazeData (walls = solid) and returns tile paths.
## 4-directional to match grid movement; deterministic for a fixed maze.


static func build(maze: MazeData, cell_size: int) -> AStarGrid2D:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, maze.width, maze.height)
	astar.cell_size = Vector2(cell_size, cell_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for y in maze.height:
		for x in maze.width:
			if not maze.is_open(x, y):
				astar.set_point_solid(Vector2i(x, y), true)
	return astar


## Tile path from `from` to `to`, endpoints inclusive. Empty if either endpoint
## is out of bounds or solid.
static func path(astar: AStarGrid2D, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not astar.is_in_boundsv(from) or not astar.is_in_boundsv(to):
		return []
	if astar.is_point_solid(from) or astar.is_point_solid(to):
		return []
	return astar.get_id_path(from, to)
```

- [ ] **Step 4: Run to verify it passes**

Run: `... -gselect=test_grid_nav.gd 2>&1 | tail -8`
Expected: `3/3 passed`.

- [ ] **Step 5: Import & commit**

```bash
~/.local/bin/godot --headless --path . --import 2>&1 | tail -1
git add world/maze/grid_nav.gd world/maze/grid_nav.gd.uid tests/test_grid_nav.gd tests/test_grid_nav.gd.uid
git commit -m "Add GridNav AStarGrid2D pathfinding helper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 4: Player grid movement

Replace the player's free 8-way movement with tile-stepping via `GridMover`, add `apply_web_slow`, and unit-test the input→cardinal reduction. The rest of the game still uses old movement after this task and must still boot.

**Files:**
- Modify: `entities/player/player.gd`
- Modify: `entities/player/player.tscn` (add a `GridMover` child)
- Test: `tests/test_player_input.gd`

**Interfaces:**
- Consumes: `GridMover` (Task 2).
- Produces:
  - `static func _dominant_dir(input: Vector2) -> Vector2i` on `Player`
  - `func apply_web_slow(factor: float, duration: float) -> void` on `Player`

- [ ] **Step 1: Write the failing test**

Create `tests/test_player_input.gd`:
```gdscript
extends GutTest
## Player analog input reduces to a single cardinal grid direction.


func test_pure_axes_map_straight_through() -> void:
	assert_eq(Player._dominant_dir(Vector2(1, 0)), Vector2i.RIGHT)
	assert_eq(Player._dominant_dir(Vector2(-1, 0)), Vector2i.LEFT)
	assert_eq(Player._dominant_dir(Vector2(0, 1)), Vector2i.DOWN)
	assert_eq(Player._dominant_dir(Vector2(0, -1)), Vector2i.UP)


func test_zero_input_is_no_direction() -> void:
	assert_eq(Player._dominant_dir(Vector2.ZERO), Vector2i.ZERO)


func test_diagonal_resolves_to_dominant_axis() -> void:
	assert_eq(Player._dominant_dir(Vector2(0.9, 0.3)), Vector2i.RIGHT)
	assert_eq(Player._dominant_dir(Vector2(0.2, -0.8)), Vector2i.UP)


func test_tie_favours_horizontal() -> void:
	assert_eq(Player._dominant_dir(Vector2(0.5, 0.5)), Vector2i.RIGHT)
```

- [ ] **Step 2: Run to verify it fails**

Run: `... -gselect=test_player_input.gd 2>&1 | tail -10`
Expected: FAIL — `_dominant_dir` not found.

- [ ] **Step 3: Update the player script**

In `entities/player/player.gd`, add the `_mover` onready and remove `move_speed`. Replace the movement block. Full new movement region:

Replace lines 7-16 (the `move_speed` export through the `facing`/`_dead` vars) with:
```gdscript
@onready var health: HealthComponent = $HealthComponent
@onready var hunger: HungerComponent = $HungerComponent
@onready var web_emitter: WebEmitter = $WebEmitter
@onready var trap_placer: TrapPlacer = $TrapPlacer
@onready var sprite: Sprite2D = $Sprite
@onready var _mover: GridMover = $GridMover

var facing := Vector2.RIGHT
var _dead := false
```

Replace the whole `_physics_process` (lines 33-47) with:
```gdscript
func _physics_process(_delta: float) -> void:
	if _dead:
		return
	var dir := _dominant_dir(Input.get_vector("move_left", "move_right", "move_up", "move_down"))
	if dir != Vector2i.ZERO:
		facing = Vector2(dir)
		sprite.rotation = facing.angle() # sprite drawn facing east (rotation 0)
		_mover.try_step(dir)

	if Input.is_action_pressed("fire"):
		web_emitter.fire(global_position, facing, self)
	if Input.is_action_just_pressed("place_trap"):
		trap_placer.place(global_position, self)


## Reduce analog movement input to one cardinal grid direction (ties -> x).
static func _dominant_dir(input: Vector2) -> Vector2i:
	if input.length_squared() < 0.04:
		return Vector2i.ZERO
	if absf(input.x) >= absf(input.y):
		return Vector2i(int(signf(input.x)), 0)
	return Vector2i(0, int(signf(input.y)))


## Apply a web slow to this spider's movement (called by a web shot).
func apply_web_slow(factor: float, duration: float) -> void:
	if _mover != null:
		_mover.apply_slow(factor, duration)
```

- [ ] **Step 4: Add the GridMover node to the player scene**

In `entities/player/player.tscn`:
- Add to the `[ext_resource]` block (pick the next free id, e.g. `id="10_mover"`):
  `[ext_resource type="Script" path="res://components/grid_mover.gd" id="10_mover"]`
- Add this node (child of the root `Player`, anywhere among its children):
```
[node name="GridMover" type="Node" parent="."]
script = ExtResource("10_mover")
tile_size = 48
step_time = 0.12
```

- [ ] **Step 5: Run the unit test**

Run: `... -gselect=test_player_input.gd 2>&1 | tail -8`
Expected: `4/4 passed`.

- [ ] **Step 6: Import & boot smoke test**

```
~/.local/bin/godot --headless --path . --import 2>&1 | tail -1
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 300 2>&1 | grep -Ei 'error|script error' || echo CLEAN
```
Expected: `CLEAN` (game boots; player now grid-steps, enemy still on navmesh).

- [ ] **Step 7: Commit**

```bash
git add entities/player/player.gd entities/player/player.tscn tests/test_player_input.gd tests/test_player_input.gd.uid
git commit -m "Player moves on the tile grid via GridMover

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 5: Larva grid wander + web_kill

Larvae wander cell-to-cell (avoiding immediate reversal unless dead-ended) via `GridMover`, and gain `web_kill()` which drops them from the `larvae` group and leaves an inedible corpse decal.

**Files:**
- Modify: `entities/larva/larva.gd`
- Modify: `entities/larva/larva.tscn` (add a `GridMover` child)
- Test: `tests/test_larva.gd`

**Interfaces:**
- Consumes: `GridMover` (Task 2), `web_shot_spent.tscn` (existing, as the corpse decal).
- Produces: `func web_kill() -> void` on `Larva` — removes from group `larvae`, spawns a corpse decal, frees the larva.

- [ ] **Step 1: Write the failing test**

Create `tests/test_larva.gd`:
```gdscript
extends GutTest
## A web-killed larva leaves the larvae group so nobody can eat it.


func test_web_kill_removes_from_larvae_group() -> void:
	var larva := Larva.new()
	add_child_autofree(larva)
	assert_true(larva.is_in_group("larvae"), "spawns in the larvae group")
	larva.web_kill()
	assert_false(larva.is_in_group("larvae"), "web-killed larva is no longer edible")


func test_web_kill_is_idempotent() -> void:
	var larva := Larva.new()
	add_child_autofree(larva)
	larva.web_kill()
	larva.web_kill() # must not error on an already-killed larva
	assert_false(larva.is_in_group("larvae"))
```

- [ ] **Step 2: Run to verify it fails**

Run: `... -gselect=test_larva.gd 2>&1 | tail -10`
Expected: FAIL — `web_kill` not found.

- [ ] **Step 3: Rewrite the larva script**

Replace the entire contents of `entities/larva/larva.gd` with:
```gdscript
class_name Larva
extends CharacterBody2D
## A wandering creature. Steps cell-to-cell on the maze grid, avoiding an
## immediate reversal unless it is dead-ended. Freezes when a trap catches it,
## and can be killed (not eaten) by a web shot, leaving an inedible corpse.
## Body collides with walls only (mask = world) so it passes through traps and
## spiders until a trap's catch area grabs it.

const CorpseScene := preload("res://entities/web/web_shot_spent.tscn")

@onready var _mover: GridMover = $GridMover

var caught := false
var _dead := false
var _last_dir := Vector2i.RIGHT


func _ready() -> void:
	add_to_group("larvae")


## Set initial facing (Level derives this from the spawn tile's type).
func set_facing(dir: Vector2i) -> void:
	if dir != Vector2i.ZERO:
		_last_dir = dir
		rotation = Vector2(dir).angle()


## Called by a trap: stop and snap to the trap centre.
func set_caught(at_position: Vector2) -> void:
	caught = true
	global_position = at_position


func _physics_process(_delta: float) -> void:
	if caught or _dead or _mover.is_moving():
		return
	_wander_step()


func _wander_step() -> void:
	# Prefer any non-reverse direction; fall back to reversing at a dead-end.
	var options: Array[Vector2i] = []
	for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if d != -_last_dir:
			options.append(d)
	options.shuffle()
	options.append(-_last_dir)
	for d in options:
		if _mover.try_step(d):
			_last_dir = d
			rotation = Vector2(d).angle()
			return


## A web shot killed this larva: drop out of the edible pool, leave a corpse.
func web_kill() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("larvae")
	var holder := get_parent()
	if holder != null:
		var corpse := CorpseScene.instantiate()
		holder.add_child(corpse)
		corpse.global_position = global_position
	queue_free()
```

- [ ] **Step 4: Add the GridMover node to the larva scene**

In `entities/larva/larva.tscn`:
- Add ext_resource: `[ext_resource type="Script" path="res://components/grid_mover.gd" id="3_mover"]`
- Add child node:
```
[node name="GridMover" type="Node" parent="."]
script = ExtResource("3_mover")
tile_size = 48
step_time = 0.14
```

- [ ] **Step 5: Run the unit test**

Run: `... -gselect=test_larva.gd 2>&1 | tail -8`
Expected: `2/2 passed`.

- [ ] **Step 6: Import & boot smoke test**

```
~/.local/bin/godot --headless --path . --import 2>&1 | tail -1
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 300 2>&1 | grep -Ei 'error|script error' || echo CLEAN
```
Expected: `CLEAN`.

- [ ] **Step 7: Commit**

```bash
git add entities/larva/larva.gd entities/larva/larva.tscn tests/test_larva.gd tests/test_larva.gd.uid
git commit -m "Larvae wander on the grid and can be web-killed

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 6: Destructible web trap

A placed `WebTrap` gains a 3-hit counter; a web shot's `take_web_hit()` decrements it and the third hit destroys the trap (leaving the existing torn-web decal).

**Files:**
- Modify: `entities/web/web_trap.gd`
- Test: `tests/test_web_trap.gd` (extend the existing file)

**Interfaces:**
- Produces: `func take_web_hit() -> void` on `WebTrap`; `@export var hits_to_destroy: int` (3); `var web_hits: int`.

- [ ] **Step 1: Add the failing tests**

Append to `tests/test_web_trap.gd`:
```gdscript
func test_third_web_hit_destroys_the_trap() -> void:
	var trap := _make_trap()
	trap.take_web_hit()
	trap.take_web_hit()
	assert_false(trap.spent, "two hits do not destroy the trap")
	trap.take_web_hit()
	assert_true(trap.spent, "the third hit destroys the trap")


func test_web_hits_ignored_once_spent() -> void:
	var trap := _make_trap()
	var pair := _make_spider(50.0)
	trap.catch_larva(_make_larva())
	trap.try_consume(pair[0]) # spent via consumption
	trap.take_web_hit() # must be a no-op, not error
	assert_true(trap.spent)
```

- [ ] **Step 2: Run to verify it fails**

Run: `... -gselect=test_web_trap.gd 2>&1 | tail -12`
Expected: FAIL — `take_web_hit` not found.

- [ ] **Step 3: Implement destructibility**

In `entities/web/web_trap.gd`, after the `@export var arm_delay` line (line 14), add:
```gdscript
## Web shots needed to destroy a placed trap.
@export var hits_to_destroy: int = 3
```
After `var spent := false` (line 18), add:
```gdscript
var web_hits := 0
```
Before `func _leave_torn_web()` (line 88), add:
```gdscript
## A web shot struck this trap. The Nth hit destroys it, leaving a torn web.
func take_web_hit() -> void:
	if spent:
		return
	web_hits += 1
	if web_hits >= hits_to_destroy:
		spent = true
		if is_instance_valid(caught_larva):
			caught_larva.queue_free()
			caught_larva = null
		_leave_torn_web()
		queue_free()
```

- [ ] **Step 4: Run to verify it passes**

Run: `... -gselect=test_web_trap.gd 2>&1 | tail -10`
Expected: all trap tests pass (7 total).

- [ ] **Step 5: Import & commit**

```bash
~/.local/bin/godot --headless --path . --import 2>&1 | tail -1
git add entities/web/web_trap.gd tests/test_web_trap.gd
git commit -m "Web traps take three web shots to destroy

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 7: Level builds the AStar grid and helpers

`Level` builds the `AStarGrid2D` (via `GridNav`), exposes tile/​world conversions and `path_tiles`, and bumps `LARVA_COUNT`. The navmesh stays for now (the enemy still uses it) and is removed in Task 8.

**Files:**
- Modify: `world/level.gd`
- Test: `tests/test_level_grid.gd`

**Interfaces:**
- Consumes: `GridNav` (Task 3).
- Produces (on `Level`):
  - `func tile_of(world: Vector2) -> Vector2i`
  - `func centre_of(tile: Vector2i) -> Vector2`
  - `func path_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]`
  - `LARVA_COUNT` now `6`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_level_grid.gd`:
```gdscript
extends GutTest
## Level's tile<->world conversions round-trip on tile centres.


func test_tile_of_and_centre_of_round_trip() -> void:
	var level := preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	# centre_of a tile, then tile_of that point, returns the same tile.
	for tile in [Vector2i(1, 1), Vector2i(3, 5), Vector2i(8, 8)]:
		var centre := level.centre_of(tile)
		assert_eq(level.tile_of(centre), tile, "round-trips tile %s" % tile)


func test_centre_is_tile_middle() -> void:
	var level := preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	assert_eq(level.centre_of(Vector2i(0, 0)), Vector2(24, 24))
```

- [ ] **Step 2: Run to verify it fails**

Run: `... -gselect=test_level_grid.gd 2>&1 | tail -10`
Expected: FAIL — `centre_of` not found.

- [ ] **Step 3: Add the grid to Level**

In `world/level.gd`:

Change `const LARVA_COUNT := 4` to:
```gdscript
const LARVA_COUNT := 6
```

After `var enemy: Node2D` (line 30), add:
```gdscript
var _astar: AStarGrid2D
```

In `build()` (line 34), after `_build_collision_and_occluders()` and before `_build_navigation()`, add:
```gdscript
	_astar = GridNav.build(maze, TILE_SIZE)
```

After the `map_center()` function (line 53), add:
```gdscript
## Grid <-> world conversions and pathing, used by grid-moving entities.
func tile_of(world: Vector2) -> Vector2i:
	return Vector2i(int(world.x / TILE_SIZE), int(world.y / TILE_SIZE))


func centre_of(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * TILE_SIZE, (tile.y + 0.5) * TILE_SIZE)


func path_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if _astar == null:
		return []
	return GridNav.path(_astar, from, to)
```

- [ ] **Step 4: Run to verify it passes**

Run: `... -gselect=test_level_grid.gd 2>&1 | tail -8`
Expected: `2/2 passed`.

- [ ] **Step 5: Import & boot smoke test**

```
~/.local/bin/godot --headless --path . --import 2>&1 | tail -1
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 300 2>&1 | grep -Ei 'error|script error' || echo CLEAN
```
Expected: `CLEAN` (six larvae now spawn; enemy still on navmesh).

- [ ] **Step 6: Commit**

```bash
git add world/level.gd tests/test_level_grid.gd tests/test_level_grid.gd.uid
git commit -m "Level builds AStar grid, tile helpers, six larvae

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 8: Enemy grid movement and pathing

Rewrite the enemy's movement layer to step on the grid via `GridMover`, pathing with `Level.path_tiles` (chase/seek) and greedy stepping (patrol/flee). Remove `NavigationAgent2D`. `Level` binds itself to the enemy and, since nothing uses the navmesh anymore, its construction and the `NavRegion` node are deleted. Add `apply_web_slow`. The FSM and perception logic are unchanged.

**Files:**
- Modify: `entities/enemy/enemy.gd`
- Modify: `entities/enemy/enemy.tscn` (add `GridMover`, remove `NavigationAgent2D`)
- Modify: `world/level.gd` (bind level to enemy; delete `_build_navigation`/`_corner_index`; drop `_nav_region`)
- Modify: `world/level.tscn` (remove the `NavRegion` node)
- Test: `tests/test_enemy_path.gd`

**Interfaces:**
- Consumes: `GridMover` (Task 2), `Level.path_tiles`/`tile_of`/`centre_of` (Task 7).
- Produces (on `Enemy`):
  - `func bind_level(level: Node) -> void`
  - `static func _step_dir(from: Vector2i, to: Vector2i) -> Vector2i` — clamped unit step toward `to`.
  - `func apply_web_slow(factor: float, duration: float) -> void`

- [ ] **Step 1: Write the failing test**

Create `tests/test_enemy_path.gd`:
```gdscript
extends GutTest
## The pure step-direction helper the enemy uses to follow a tile path.


func test_step_dir_is_a_unit_cardinal_toward_target() -> void:
	assert_eq(Enemy._step_dir(Vector2i(2, 2), Vector2i(5, 2)), Vector2i.RIGHT)
	assert_eq(Enemy._step_dir(Vector2i(2, 2), Vector2i(2, 0)), Vector2i.UP)
	assert_eq(Enemy._step_dir(Vector2i(2, 2), Vector2i(1, 2)), Vector2i.LEFT)


func test_step_dir_same_tile_is_zero() -> void:
	assert_eq(Enemy._step_dir(Vector2i(3, 3), Vector2i(3, 3)), Vector2i.ZERO)
```

- [ ] **Step 2: Run to verify it fails**

Run: `... -gselect=test_enemy_path.gd 2>&1 | tail -10`
Expected: FAIL — `_step_dir` not found.

- [ ] **Step 3: Rewrite the enemy movement layer**

Replace the entire contents of `entities/enemy/enemy.gd` with:
```gdscript
class_name Enemy
extends CharacterBody2D
## The rival spider. A data-driven EnemyType sets base stats; depth scales them.
## An enum FSM drives behaviour — patrol / seek_food / chase / flee — stepping
## on the maze grid via GridMover. Chase and food-seeking path with the level's
## AStarGrid2D; patrol and flee step greedily. It hungers like the player, eats
## larvae by contact, and can be starved out as well as killed.

enum State { PATROL, SEEK_FOOD, CHASE, FLEE }

@export var enemy_type: EnemyType

## Behaviour tuning (design §10 — feel these out in playtest).
@export var vision_range: float = 240.0
@export var attack_range: float = 200.0
@export var flee_health_fraction: float = 0.3
@export var hungry_fraction: float = 0.6
@export var repath_interval: float = 0.35
## Distance at which the enemy eats a larva by contact.
@export var eat_range: float = 30.0
## Hunger removed by eating one larva.
@export var eat_satiation: float = 40.0

@onready var health: HealthComponent = $HealthComponent
@onready var hunger: HungerComponent = $HungerComponent
@onready var web_emitter: WebEmitter = $WebEmitter
@onready var trap_placer: TrapPlacer = $TrapPlacer
@onready var _mover: GridMover = $GridMover
@onready var facing_visual: Node2D = get_node_or_null("Sprite")

var state: State = State.PATROL

var _player: Node2D
var _level: Node
var _repath_left := 0.0
var _facing := Vector2.RIGHT
var _dead := false
var _path: Array[Vector2i] = []
var _path_i := 0


## Level calls this right after instancing so the enemy can path on the grid.
func bind_level(level: Node) -> void:
	_level = level


func _ready() -> void:
	add_to_group("spiders")
	add_to_group("enemy")
	_apply_type()
	health.died.connect(_on_died)
	_player = get_tree().get_first_node_in_group("player") as Node2D


func _apply_type() -> void:
	var depth_mult := GameState.depth_scale()
	if enemy_type != null:
		health.max_health = enemy_type.max_health * depth_mult
		hunger.hunger_rate = enemy_type.hunger_rate * depth_mult
	else:
		health.max_health *= depth_mult
	health.current_health = health.max_health


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D

	_update_state()

	_repath_left -= delta
	match state:
		State.CHASE:
			_do_chase()
		State.FLEE:
			_do_flee()
		State.SEEK_FOOD:
			_do_seek_food()
		State.PATROL:
			_do_patrol()


func _update_state() -> void:
	var next := state
	if health.fraction() <= flee_health_fraction:
		next = State.FLEE
	elif _can_see_player():
		next = State.CHASE
	elif hunger.fraction() >= hungry_fraction:
		next = State.SEEK_FOOD
	else:
		next = State.PATROL

	if next != state:
		state = next
		_repath_left = 0.0
		_path = []


# --- per-state behaviour ------------------------------------------------------

func _do_chase() -> void:
	if _player == null:
		return
	if _repath_left <= 0.0:
		_set_path_to(_tile_of(_player.global_position))
		_repath_left = repath_interval
	_follow_path()
	var to_player := _player.global_position - global_position
	if to_player.length() <= attack_range and _has_line_of_sight(_player.global_position):
		web_emitter.fire(global_position, to_player, self)


func _do_seek_food() -> void:
	var larva := _nearest_in_group("larvae")
	if larva == null:
		_do_patrol()
		return
	if global_position.distance_to(larva.global_position) <= eat_range:
		_eat_larva(larva)
		return
	if _repath_left <= 0.0:
		_set_path_to(_tile_of(larva.global_position))
		_repath_left = repath_interval
	_follow_path()


func _do_flee() -> void:
	if _mover.is_moving():
		return
	var away := (global_position - _player.global_position) if _player != null else Vector2.RIGHT
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var dir := _dominant(away)
	if not _mover.try_step(dir):
		_mover.try_step(_dominant(Vector2(away.y, -away.x))) # try a perpendicular
	_face(dir)


func _do_patrol() -> void:
	if _mover.is_moving():
		return
	# Greedy random walk on open tiles.
	var options: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	options.shuffle()
	for d in options:
		if _mover.try_step(d):
			_face(d)
			return


# --- grid path following ------------------------------------------------------

func _set_path_to(target_tile: Vector2i) -> void:
	if _level == null:
		_path = []
		return
	_path = _level.path_tiles(_tile_of(global_position), target_tile)
	_path_i = 0


func _follow_path() -> void:
	if _mover.is_moving() or _path.is_empty() or _path_i >= _path.size():
		return
	var my_tile := _tile_of(global_position)
	var dir := _step_dir(my_tile, _path[_path_i])
	if dir == Vector2i.ZERO:
		_path_i += 1
		return
	if _mover.try_step(dir):
		_face(dir)
		_path_i += 1
	else:
		_path = [] # blocked (e.g. a trap dropped in the lane) — repath next tick


## Clamped unit step from `from` toward `to` (cardinal; ties favour x).
static func _step_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	if d == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


func _dominant(v: Vector2) -> Vector2i:
	if absf(v.x) >= absf(v.y):
		return Vector2i(int(signf(v.x)), 0)
	return Vector2i(0, int(signf(v.y)))


func _face(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	_facing = Vector2(dir)
	if facing_visual != null:
		facing_visual.rotation = _facing.angle()


func _tile_of(world: Vector2) -> Vector2i:
	if _level != null:
		return _level.tile_of(world)
	return Vector2i(int(world.x / 48.0), int(world.y / 48.0))


# --- eating -------------------------------------------------------------------

func _eat_larva(larva: Node) -> void:
	if not larva.is_in_group("larvae"):
		return
	hunger.satiate(eat_satiation)
	EventBus.larva_consumed.emit(self, 0.0)
	larva.queue_free()


# --- perception ---------------------------------------------------------------

func _can_see_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if global_position.distance_to(_player.global_position) > vision_range:
		return false
	return _has_line_of_sight(_player.global_position)


func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos, 1) # world layer
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _nearest_in_group(group: String) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group(group):
		var n := node as Node2D
		if n == null:
			continue
		var d := global_position.distance_squared_to(n.global_position)
		if d < best_dist:
			best_dist = d
			best = n
	return best


## Apply a web slow to this spider's movement (called by a web shot).
func apply_web_slow(factor: float, duration: float) -> void:
	if _mover != null:
		_mover.apply_slow(factor, duration)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	var cause := "starved" if hunger.is_starving() else "killed"
	EventBus.enemy_defeated.emit(cause)
	queue_free()
```

- [ ] **Step 4: Update the enemy scene**

In `entities/enemy/enemy.tscn`:
- **Remove** the `NavigationAgent2D` node block (lines 45-48).
- Add ext_resource: `[ext_resource type="Script" path="res://components/grid_mover.gd" id="11_mover"]`
- Add child node:
```
[node name="GridMover" type="Node" parent="."]
script = ExtResource("11_mover")
tile_size = 48
step_time = 0.16
```
(step_time 0.16 = a touch slower than the player's 0.12, replacing the old `move_speed`-based speed.)

- [ ] **Step 5: Bind the level to the enemy and delete the navmesh**

In `world/level.gd`:

Remove the `@onready var _nav_region: NavigationRegion2D = $NavRegion` line (line 23).

In `build()`, remove the `_build_navigation()` call (line 38).

In `_spawn_entities()`, after `enemy = EnemyScene.instantiate()` and before `_entities.add_child(enemy)`, add:
```gdscript
	enemy.bind_level(self)
```

Delete the whole `_build_navigation()` function (lines 91-113) and the `_corner_index()` function (lines 116-122).

In `world/level.tscn`, **remove** the `NavRegion` node:
```
[node name="NavRegion" type="NavigationRegion2D" parent="."]
```

- [ ] **Step 6: Run the unit test**

Run: `... -gselect=test_enemy_path.gd 2>&1 | tail -8`
Expected: `2/2 passed`.

- [ ] **Step 7: Import & boot smoke test**

```
~/.local/bin/godot --headless --path . --import 2>&1 | tail -1
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 400 2>&1 | grep -Ei 'error|script error|navigation' || echo CLEAN
```
Expected: `CLEAN` — no NavigationServer warnings, enemy grid-steps and paths.

- [ ] **Step 8: Commit**

```bash
git add entities/enemy/enemy.gd entities/enemy/enemy.tscn world/level.gd world/level.tscn tests/test_enemy_path.gd tests/test_enemy_path.gd.uid
git commit -m "Enemy paths on the grid; drop the navmesh

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 9: Enemy sustains itself (hunger retune)

The enemy already eats by contact (Task 8). This task slows its hunger clock so it can realistically stay fed, and guards the retune with a test that an enemy which reaches food does not starve over a simulated window.

**Files:**
- Modify: `resources/enemies/rival_spider.tres` (`hunger_rate` 3.0 → 1.2)
- Modify: `entities/enemy/enemy.tscn` (`HungerComponent.hunger_rate` 3.0 → 1.2, for scene-preview consistency; the `.tres` is the runtime source of truth via `_apply_type`)
- Test: `tests/test_enemy_hunger.gd`

**Interfaces:**
- Consumes: `HungerComponent.tick` (existing), `EnemyType.hunger_rate`.
- Produces: no new symbols — a tuning + guard test.

- [ ] **Step 1: Write the failing test**

Create `tests/test_enemy_hunger.gd`:
```gdscript
extends GutTest
## Guards the enemy hunger retune: the rival's configured hunger_rate is slow
## enough that periodic feeding keeps it alive.


func test_rival_hunger_rate_is_retuned() -> void:
	var rival: EnemyType = preload("res://resources/enemies/rival_spider.tres")
	assert_almost_eq(rival.hunger_rate, 1.2, 0.001,
		"rival hunger_rate lowered so it can feed itself")


func test_periodic_feeding_prevents_starvation() -> void:
	# Simulate: hunger rises at the rival rate; a meal every ~8s keeps it below max.
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.hunger_rate = 1.2
	hunger.current_hunger = 0.0
	autofree(hunger)
	var t := 0.0
	while t < 60.0:
		hunger.tick(0.5)
		t += 0.5
		if fmod(t, 8.0) < 0.5: # a contact meal roughly every 8 seconds
			hunger.satiate(40.0)
	assert_false(hunger.is_starving(),
		"a fed enemy at hunger_rate 1.2 does not starve")
```

- [ ] **Step 2: Run to verify it fails**

Run: `... -gselect=test_enemy_hunger.gd 2>&1 | tail -10`
Expected: FAIL — first test asserts 1.2 but the `.tres` still holds 3.0.

- [ ] **Step 3: Retune the resource and scene**

In `resources/enemies/rival_spider.tres`, change:
```
hunger_rate = 3.0
```
to:
```
hunger_rate = 1.2
```

In `entities/enemy/enemy.tscn`, change the `HungerComponent` line:
```
hunger_rate = 3.0
```
to:
```
hunger_rate = 1.2
```

- [ ] **Step 4: Run to verify it passes**

Run: `... -gselect=test_enemy_hunger.gd 2>&1 | tail -8`
Expected: `2/2 passed`.

- [ ] **Step 5: Import & commit**

```bash
~/.local/bin/godot --headless --path . --import 2>&1 | tail -1
git add resources/enemies/rival_spider.tres entities/enemy/enemy.tscn tests/test_enemy_hunger.gd tests/test_enemy_hunger.gd.uid
git commit -m "Retune enemy hunger so it feeds itself instead of starving

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 10: Web shot redesign

Widen the web shot's detection and branch by target: enemy/player hurtbox → reduced damage + slow; larva → `web_kill`; placed trap → `take_web_hit`; wall → splat. Damage drops to 8; only walls leave a splat (larva/trap already leave their own decal).

**Files:**
- Modify: `entities/web/web_shot.gd`
- Modify: `entities/web/web_shot.tscn` (`collision_mask` 17 → 57)
- Test: `tests/test_web_shot.gd`

**Interfaces:**
- Consumes: `Hurtbox.receive_hit` (existing), `Player.apply_web_slow`/`Enemy.apply_web_slow` (Tasks 4/8), `Larva.web_kill` (Task 5), `WebTrap.take_web_hit` (Task 6).
- Produces: `@export var damage` (8.0), `@export var slow_factor` (0.4), `@export var slow_duration` (2.0) on the web shot; new body-branching in `_on_body_entered`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_web_shot.gd`:
```gdscript
extends GutTest
## Web shot routes a hit to the right effect based on what it struck. Drives the
## body/area handlers directly with stand-ins (no physics frames needed).

const WebShotScene := preload("res://entities/web/web_shot.tscn")


func _make_shot() -> Area2D:
	var shot := WebShotScene.instantiate()
	add_child_autofree(shot)
	return shot


func test_hitting_a_larva_web_kills_it() -> void:
	var shot := _make_shot()
	var larva := Larva.new()
	add_child_autofree(larva)
	shot._on_body_entered(larva)
	assert_false(larva.is_in_group("larvae"), "larva is web-killed, not eaten")


func test_hitting_a_trap_registers_a_web_hit() -> void:
	var shot := _make_shot()
	var trap := WebTrap.new()
	add_child_autofree(trap)
	shot._on_body_entered(trap)
	assert_eq(trap.web_hits, 1, "one web hit registered on the trap")


func test_reduced_damage_default() -> void:
	var shot := _make_shot()
	assert_almost_eq(shot.damage, 8.0, 0.001, "web damage lowered from 20 to 8")
```

- [ ] **Step 2: Run to verify it fails**

Run: `... -gselect=test_web_shot.gd 2>&1 | tail -12`
Expected: FAIL — `damage` still 20 and larva/trap branches absent (larva stays in group).

- [ ] **Step 3: Update the web shot script**

In `entities/web/web_shot.gd`:

Change the exports (lines 9-11) to:
```gdscript
@export var speed: float = 340.0
@export var damage: float = 8.0
@export var max_lifetime: float = 2.0
## Movement slow applied to a spider the shot hits, and how long it lasts.
@export var slow_factor: float = 0.4
@export var slow_duration: float = 2.0
```

Replace `_on_body_entered` (lines 39-44) with:
```gdscript
func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	if body is WebTrap:
		body.take_web_hit()
		_despawn()
		return
	if body.is_in_group("larvae"):
		if body.has_method("web_kill"):
			body.web_kill()
		_despawn()
		return
	# Anything else in our mask is a wall/world body — end the shot with a splat.
	_leave_splat()
	_despawn()
```

Replace `_on_area_entered` (lines 57-63) with:
```gdscript
func _on_area_entered(area: Area2D) -> void:
	if _spent or not (area is Hurtbox):
		return
	if _is_source(area):
		return
	area.receive_hit(damage, _source)
	var entity := area.get_parent()
	if entity != null and entity.has_method("apply_web_slow"):
		entity.apply_web_slow(slow_factor, slow_duration)
	_despawn()
```

- [ ] **Step 4: Widen the collision mask**

In `entities/web/web_shot.tscn`, change:
```
collision_mask = 17
```
to (world 1 + larva 8 + hurtbox 16 + trap 32 = 57):
```
collision_mask = 57
```

- [ ] **Step 5: Run to verify it passes**

Run: `... -gselect=test_web_shot.gd 2>&1 | tail -8`
Expected: `3/3 passed`.

- [ ] **Step 6: Import & boot smoke test**

```
~/.local/bin/godot --headless --path . --import 2>&1 | tail -1
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 400 2>&1 | grep -Ei 'error|script error' || echo CLEAN
```
Expected: `CLEAN`.

- [ ] **Step 7: Commit**

```bash
git add entities/web/web_shot.gd entities/web/web_shot.tscn tests/test_web_shot.gd tests/test_web_shot.gd.uid
git commit -m "Web shots damage+slow spiders, kill larvae, hit traps

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_014WhKpuzmfoxFtBrc5icJUK"
```

---

### Task 11: Full-suite validation and integration boot

Confirm every test passes together and the whole game boots and runs a sustained window with grid movement, enemy pathing, and web interactions all live.

**Files:**
- None (verification only).

- [ ] **Step 1: Run the entire test suite**

Run:
```
~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20
```
Expected: `---- All tests passed! ----`, with the new suites included (grid_mover, grid_nav, player_input, larva, level_grid, enemy_path, enemy_hunger, web_shot, plus the extended web_trap and the original maze/tile/health/hunger tests).

- [ ] **Step 2: Sustained boot with error grep**

Run:
```
~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 900 2>&1 | grep -Ei 'error|script error|navigation|leaked' || echo CLEAN
```
Expected: `CLEAN` — no runtime errors, no NavigationServer references, no leaked-node spam over ~15s of simulated play.

- [ ] **Step 3: Update the validation memory**

Append the GUT run command to `~/.claude/projects/-home-e3h1x-workspace-burrow/memory/godot-validation-workflow.md` so future sessions know tests now run headlessly:
- Note: `GUT 9.4.0 is vendored at addons/gut/. Run the suite with`
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`
  `— autoloads DO load under the cmdln runner (EventBus-using tests pass).`

- [ ] **Step 4: Final confirmation (no commit needed unless memory changed)**

If the memory file changed, it is outside the repo — no git commit. Confirm `git status` in the repo is clean (all task commits landed):
```
git status --short
```
Expected: empty (clean working tree).

---

## Self-Review

**Spec coverage:**
- §1 GridMover → Task 2. ✓
- §2 Player/enemy/larva grid movement → Tasks 4 (player), 8 (enemy), 5 (larva). ✓
- §3 AStarGrid2D + navmesh removal → Tasks 3 (GridNav), 7 (build), 8 (wire + delete navmesh/NavRegion). ✓
- §4 Web redesign (damage+slow / kill larvae / 3-hit trap) → Tasks 10 (shot + slow forwarding), 5 (`web_kill`), 6 (`take_web_hit`); `apply_web_slow` on player (Task 4) and enemy (Task 8). ✓
- §5 Enemy contact eating + hunger retune → Tasks 8 (`_eat_larva`), 9 (retune + guard). ✓
- §6 `LARVA_COUNT` 4→6 → Task 7. ✓
- §7 Camera/fog/HUD unchanged → no task touches them; boot tests confirm no regressions. ✓
- §8 Testing → each task is TDD; Task 11 runs the full suite + integration boot. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has an expected result. ✓

**Type consistency:** `GridMover` API (`try_step`/`is_moving`/`tick`/`apply_slow`/`step_time`/`tile_size`/`speed_scale`/`block_check`/`step_finished`) is defined in Task 2 and used identically in Tasks 4/5/8. `Level.tile_of`/`centre_of`/`path_tiles` defined in Task 7, used in Task 8. `GridNav.build`/`path` defined in Task 3, used in Task 7. `web_kill` (Task 5), `take_web_hit`/`web_hits` (Task 6), `apply_web_slow` (Tasks 4/8) all match their call sites in Task 10. `Enemy.bind_level`/`_step_dir` defined in Task 8, `bind_level` called from Level in Task 8. ✓

## Notes / decisions folded in from spec review

- **Splat suppression:** web shots leave the wall-splat decal *only* on wall hits. Larva hits leave the larva's own corpse decal (Task 5); trap destruction leaves the torn-web decal (Task 6). This resolves the spec's "despawn (splat)" ambiguity for larva/trap hits in favour of no double-decal.
- **Caught larva on trap destruction:** freed along with the trap (mirrors consumption), Task 6.
- **Enemy speed** now comes from `GridMover.step_time` (0.16), not `move_speed`; the old `move_speed`/`enemy_type.move_speed` scaling is dropped from the movement path. `EnemyType.move_speed` remains on the resource, unused by movement (harmless; left for a future speed-scaling pass).
