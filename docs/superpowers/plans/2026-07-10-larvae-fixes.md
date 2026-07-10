# Larvae Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Slow larvae down (baseline + weight-based-as-they-grow) and stop them from crossing floor holes/water, per playtest feedback.

**Architecture:** Two independent additions to `Larva`: a growth-driven `step_time` multiplier layered on top of `GridMover`'s existing (and untouched) `speed_scale` web-slow lever, and a `GridMover.block_check` wired to `Level.is_blocked()` — the exact pattern `Player`/`Enemy` already use for wall/pit blocking.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-10-larvae-fixes-design.md` — read once for full context.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1 | tail -30`
  (drop `-gselect=` for the whole suite). Expect `All tests passed!`.
- Import check after any `.tscn` edit: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- The growth-driven slowdown must modify `GridMover.step_time`, never `speed_scale` — `speed_scale` is exclusively owned by the temporary web-entangle slow (`apply_slow()`), and its expiry timer resets it to `1.0`, which would silently erase a `speed_scale`-based growth effect.
- This slice touches only `entities/larva/larva.gd`, `entities/larva/larva.tscn`, `world/level.gd` (one call site), and their tests. No other class/system.

---

### Task 1: Baseline and weight-based movement slowdown

**Files:**
- Modify: `entities/larva/larva.gd`
- Modify: `entities/larva/larva.tscn`
- Test: `tests/test_larva.gd`

**Interfaces:**
- Consumes: `LarvaGrowth.size_scale: float` (`entities/larva/larva_growth.gd` — already ranges `1.0` to a `2.5` cap, unchanged by this task), `GridMover.step_time: float` (`components/grid_mover.gd` — already exported, unchanged).
- Produces: `Larva._base_step_time: float` (captured once at `_ready()`), `Larva._apply_growth_speed() -> void` (private, called from `_wander_step()` and `nudge_toward()` — no other task depends on this).

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_larva.gd` (after the existing `test_wander_is_unaffected_by_an_empty_web` function):

```gdscript
func test_step_time_scales_with_growth_at_baseline() -> void:
	var larva := _make_larva()
	larva.growth.size_scale = 1.0
	larva._wander_step()
	assert_almost_eq(larva._mover.step_time, larva._base_step_time, 0.001)


func test_step_time_scales_with_growth_at_a_midpoint() -> void:
	var larva := _make_larva()
	larva.growth.size_scale = 1.75
	larva._wander_step()
	assert_almost_eq(larva._mover.step_time, larva._base_step_time * 1.75, 0.001)


func test_step_time_scales_with_growth_at_the_cap() -> void:
	var larva := _make_larva()
	larva.growth.size_scale = 2.5
	larva._wander_step()
	assert_almost_eq(larva._mover.step_time, larva._base_step_time * 2.5, 0.001)


func test_nudge_toward_also_applies_growth_speed() -> void:
	var larva := _make_larva()
	larva.growth.size_scale = 2.0
	larva.nudge_toward(larva.global_position + Vector2(100, 0))
	assert_almost_eq(larva._mover.step_time, larva._base_step_time * 2.0, 0.001)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_larva.gd 2>&1 | tail -40`
Expected: FAIL — `_base_step_time` not found on `Larva` (the property doesn't exist yet).

- [ ] **Step 3: Write the implementation**

In `entities/larva/larva.gd`, add a new field right after the existing `var _base_sprite_scale := Vector2.ONE` line:

```gdscript
var _base_step_time: float = 0.0
```

Change `_ready()` from:

```gdscript
func _ready() -> void:
	add_to_group("larvae")
	_mover.step_finished.connect(_on_step_finished)
	if _sprite != null:
		_base_sprite_scale = _sprite.scale
```

to:

```gdscript
func _ready() -> void:
	add_to_group("larvae")
	_base_step_time = _mover.step_time
	_mover.step_finished.connect(_on_step_finished)
	if _sprite != null:
		_base_sprite_scale = _sprite.scale
```

Add a new private method (anywhere below `_ready()`, e.g. right before `_wander_step()`):

```gdscript
## The fatter a larva gets, the slower its max movement speed: layered on
## GridMover.step_time (never speed_scale, which the temporary web-entangle
## slow owns exclusively and would otherwise stomp on restore). Only ever
## called when the mover isn't mid-step (both call sites already guard for
## that), so this never changes step_time out from under an in-flight lerp.
func _apply_growth_speed() -> void:
	_mover.step_time = _base_step_time * growth.size_scale
```

Change `_wander_step()`'s first line from:

```gdscript
func _wander_step() -> void:
	# Prefer any non-reverse direction; fall back to reversing at a dead-end.
```

to:

```gdscript
func _wander_step() -> void:
	_apply_growth_speed()
	# Prefer any non-reverse direction; fall back to reversing at a dead-end.
```

Change `nudge_toward()` from:

```gdscript
func nudge_toward(target_position: Vector2) -> void:
	if caught or _dead or _mover.is_moving() or GameState.freeze_others:
		return
	var to_target := target_position - global_position
```

to:

```gdscript
func nudge_toward(target_position: Vector2) -> void:
	if caught or _dead or _mover.is_moving() or GameState.freeze_others:
		return
	_apply_growth_speed()
	var to_target := target_position - global_position
```

In `entities/larva/larva.tscn`, change the `GridMover` node's `step_time = 0.34` to `step_time = 0.5`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_larva.gd 2>&1 | tail -40`
Expected: `All tests passed!`, `13/13 passed` (9 pre-existing + 4 new).

- [ ] **Step 5: Import and commit**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.

```bash
git add entities/larva/larva.gd entities/larva/larva.tscn tests/test_larva.gd
git commit -m "Slow larvae down at baseline and further as they grow"
```

---

### Task 2: Block larvae from crossing holes and water

**Files:**
- Modify: `entities/larva/larva.gd`
- Modify: `world/level.gd`
- Test: `tests/test_larva_hazards.gd` (new)

**Interfaces:**
- Consumes: `Level.is_blocked(tile: Vector2i, plane: Level.Layer) -> bool`, `Level.tile_of(world: Vector2) -> Vector2i`, `Level.Layer.GROUND` (all `world/level.gd`, unchanged, already used identically by `Player._blocked()`). `GridMover.block_check: Callable` (`components/grid_mover.gd`, unchanged).
- Produces: `Larva.bind_level(level: Level) -> void`, `Larva._blocked(dir: Vector2i) -> bool` — no other task depends on these.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_larva_hazards.gd`:

```gdscript
extends GutTest
## Larva hazard-blocking (playtest fix, sub-project C): a pit/flood tile
## blocks a larva's ground stepping exactly like a wall does, mirroring
## Player._blocked()'s existing ground-plane check (see
## test_player_ceiling_traversal.gd, whose _make_level() pattern this
## reuses). Building a real, fully-built Level also proves
## Level._spawn_larva_at() actually wires bind_level() — if it didn't, the
## spawned larva's _level would be null and the blocked-check would
## silently fall through to open ground instead of catching the pit.

const LarvaScene := preload("res://entities/larva/larva.tscn")


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _first_larva(level: Level) -> Larva:
	return level.get_tree().get_nodes_in_group("larvae")[0] as Larva


func test_a_pit_blocks_a_spawned_larvas_ground_stepping() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y) # guarantee open regardless of maze layout
	level.set_pit_at(ahead, true)

	assert_true(larva._blocked(Vector2i(1, 0)), "a pit blocks the larva's ground stepping")


func test_open_ground_does_not_block_a_spawned_larva() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)

	assert_false(larva._blocked(Vector2i(1, 0)), "open ground never blocks")


func test_a_wall_blocks_a_spawned_larva() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var wall := tile + Vector2i(1, 0)
	level.maze.set_wall(wall.x, wall.y)

	assert_true(larva._blocked(Vector2i(1, 0)), "a wall blocks the larva too")


func test_a_bare_larva_never_bound_to_a_level_falls_through_to_test_move() -> void:
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)

	# No _level set at all — must not error. With no physical collider
	# nearby, test_move reports open (not blocked).
	assert_false(larva._blocked(Vector2i(1, 0)))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_larva_hazards.gd 2>&1 | tail -30`
Expected: FAIL — `_blocked` not found on `Larva` (the method doesn't exist yet).

- [ ] **Step 3: Write the implementation**

In `entities/larva/larva.gd`, add a new field near the top (after `var _base_step_time: float = 0.0`):

```gdscript
var _level: Level
```

Change `_ready()` from:

```gdscript
func _ready() -> void:
	add_to_group("larvae")
	_base_step_time = _mover.step_time
	_mover.step_finished.connect(_on_step_finished)
	if _sprite != null:
		_base_sprite_scale = _sprite.scale
```

to:

```gdscript
func _ready() -> void:
	add_to_group("larvae")
	_base_step_time = _mover.step_time
	_mover.step_finished.connect(_on_step_finished)
	_mover.block_check = _blocked
	if _sprite != null:
		_base_sprite_scale = _sprite.scale
```

Add two new public/private methods (e.g. right after `_ready()`):

```gdscript
## Called by Level right after instancing, mirroring Player/Enemy/Earthworm's
## own bind_level() — lets the larva's blocking check resolve pit/water
## hazards without the maze data being handed to it directly.
func bind_level(level: Level) -> void:
	_level = level


## Blocking seam for GridMover: a pit or flood tile stops a larva exactly
## like a wall does (Player._blocked()'s ground-plane check, unchanged and
## reused here) — larvae have no plane/noclip/spider-contest concerns, so
## this is the ground-only branch of that same pattern. Falls through to
## the physical test_move check when _level is null (a bare Larva never
## bound to a level, as some tests construct it).
func _blocked(dir: Vector2i) -> bool:
	if _level != null:
		var target := _level.tile_of(global_position) + dir
		if _level.is_blocked(target, Level.Layer.GROUND):
			return true
	return test_move(global_transform, Vector2(dir) * float(_mover.tile_size))
```

In `world/level.gd`, change `_spawn_larva_at()` from:

```gdscript
func _spawn_larva_at(cell: Vector2i) -> void:
	var larva := LarvaScene.instantiate()
	larva.position = _tile_centre(cell.x, cell.y)
	_entities.add_child(larva)
	if larva.has_method("set_facing"):
		larva.set_facing(TileTypes.default_facing(maze.classify(cell.x, cell.y)))
```

to:

```gdscript
func _spawn_larva_at(cell: Vector2i) -> void:
	var larva := LarvaScene.instantiate()
	larva.position = _tile_centre(cell.x, cell.y)
	_entities.add_child(larva)
	larva.bind_level(self)
	if larva.has_method("set_facing"):
		larva.set_facing(TileTypes.default_facing(maze.classify(cell.x, cell.y)))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_larva_hazards.gd 2>&1 | tail -30`
Expected: `All tests passed!`, `4/4 passed`.

- [ ] **Step 5: Run the full suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20`
Expected: `All tests passed!` (no regressions — in particular, `test_larva.gd`'s existing wander/step-finished/caught tests, which construct a bare `Larva` with no `Level`, must still pass since `_blocked()` falls through cleanly when `_level` is null).

- [ ] **Step 6: Import and commit**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.

```bash
git add entities/larva/larva.gd world/level.gd tests/test_larva_hazards.gd
git commit -m "Block larvae from crossing floor holes and water"
```

---

### Task 3: Full-suite verification and manual smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full automated test suite**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tail -20`
Expected: `All tests passed!`.

- [ ] **Step 2: Import and boot smoke test**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
Run: `~/.local/bin/godot --headless --path . res://world/world.tscn --quit-after 600 2>&1 | grep -iE "error|warning|script"` — expect no new errors.

- [ ] **Step 3: Manual verification in a running Godot session**

Launch the game normally (not headless) and confirm by hand:
- Larvae visibly move slower than before, and a larva that's been alive a while (visibly larger) is noticeably slower than a freshly-spawned small one.
- Trigger or wait for a pit/flood tile near a larva and confirm it never steps onto it — it routes around, the same way it already routes around walls.

- [ ] **Step 4: Final commit (only if manual verification above required fixes)**

If Step 3 surfaced no issues, there's nothing to commit here. If it did, fix, re-run Steps 1-2, then:

```bash
git add -A
git commit -m "Fix issues found in manual larvae verification"
```
