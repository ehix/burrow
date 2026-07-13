# Environment Tiles Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give water its own distinct identity (blue marker, ring-based spreading fill and gradual drain, destroys web traps, submerges-and-restores items) layered on the existing pit-blocking overlay, and make Seismic Compaction actually destroy whatever's on a tile it collapses (permanently, unlike water) plus play a brief cosmetic cue.

**Architecture:** `WebTrap` gains a `force_destroy()` method (immediate destroy, shared by both water and compaction) alongside its existing shot-counter `take_web_hit()`. `WorldItemPickup` gains `submerge()`/`resurface()` (hide+disable / restore). `Level` gains a parallel `_water_tiles`/`_water_nodes` tracking pair and a `set_water_at()` entry point, separate from the existing pit tracking so natural pits and water can look/behave differently while sharing the same underlying `MazeData` block flag. `WaterIngress` is rewritten from one instant stamp/clear into ring-scheduled flood/drain calls against `set_water_at()`. `Level.collapse_tile_at()` gains a destroy-occupants pass and a `CombatFx.spawn_collapse_dust()` cosmetic call before the existing wall-solidify logic.

**Tech Stack:** Godot 4.7 (GDScript), GUT 9.4.0 (vendored at `addons/gut/`) for tests.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-13-environment-tiles-rework-design.md` — read once for full context.
- Godot binary: `~/.local/bin/godot`. Run GUT via:
  `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=<file>.gd 2>&1` (read the full output, not `tail`; drop `-gselect=` for the whole suite).
- Import check after any `.tscn` edit: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error` — expect no output.
- New `.gd`/`.tscn` files generate an untracked `.gd.uid`/`.tscn.uid` sidecar the first time Godot imports/runs them — after each task, run `git status` and stage any stray sidecar files.
- Water and natural pits share `MazeData`'s single `_pits` overlay for ground-blocking (unchanged — `maze.set_pit`/`is_pit`/`is_ground_blocked`), but track their own separate marker state in `Level` (`_pit_nodes` for pits, `_water_nodes`/`_water_tiles` for water, new in this plan) so they can render differently. Natural pits are entirely out of scope — never touch `set_pit_at`, `_spawn_pit_marker`, or `_pit_nodes`.
- Water is reversible (items submerge then resurface, never destroyed); compaction is permanent (items are freed outright). This asymmetry is intentional — do not "fix" one to match the other.
- Only touch the files each task's **Files** section lists. This slice touches: `entities/web/web_trap.gd`, `entities/items/world_item_pickup.gd`, `world/level.gd`, `world/hazards/water_ingress.gd`, `world/hazards/seismic_compaction.gd`, `components/combat_fx.gd`, and their tests. No other system.

---

### Task 1: `WebTrap.force_destroy()` + `WorldItemPickup.submerge()`/`resurface()`

**Files:**
- Modify: `entities/web/web_trap.gd`
- Modify: `entities/items/world_item_pickup.gd`
- Test: `tests/test_web_trap.gd` (extend)
- Test: `tests/test_world_item_pickup.gd` (extend)

**Interfaces:**
- Produces: `WebTrap.force_destroy() -> void` (consumed by Tasks 2 and 4), `WorldItemPickup.submerge() -> void` / `WorldItemPickup.resurface() -> void` (consumed by Task 2).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_web_trap.gd` (reusing its existing `_make_trap()` and `_make_larva()` helpers exactly):

```gdscript
func test_force_destroy_frees_the_trap() -> void:
	var trap := _make_trap()
	trap.force_destroy()
	assert_true(trap.spent, "force_destroy spends the trap immediately")
	assert_true(trap.is_queued_for_deletion())


func test_force_destroy_releases_a_caught_larva() -> void:
	var trap := _make_trap()
	var larva := _make_larva()
	trap.catch_larva(larva)
	trap.force_destroy()
	assert_true(larva.is_queued_for_deletion(), "a caught larva is released, not left dangling")


func test_force_destroy_ignores_hits_to_destroy() -> void:
	var trap := _make_trap()
	trap.hits_to_destroy = 3
	trap.force_destroy() # zero prior web_hits
	assert_true(trap.spent, "force_destroy works regardless of the shot counter")


func test_force_destroy_is_a_noop_on_an_already_spent_trap() -> void:
	var trap := _make_trap()
	trap.take_web_hit()
	trap.take_web_hit()
	trap.take_web_hit() # spends it via the normal 3-hit path
	assert_true(trap.spent)
	trap.force_destroy() # must not error or double-free
	assert_true(trap.spent)
```

Append to `tests/test_world_item_pickup.gd` (reusing its existing `_make_pickup()` helper exactly):

```gdscript
func test_submerge_hides_and_disables_the_pickup() -> void:
	var pickup := _make_pickup(FungusSenseItem.new())
	pickup.submerge()
	assert_false(pickup.visible)
	assert_false(pickup.monitoring)


func test_resurface_restores_visibility_and_monitoring() -> void:
	var pickup := _make_pickup(FungusSenseItem.new())
	pickup.submerge()
	pickup.resurface()
	assert_true(pickup.visible)
	assert_true(pickup.monitoring)


func test_submerged_pickup_ignores_a_spider_walking_through_it() -> void:
	var pickup := _make_pickup(FungusSenseItem.new())
	var spider := _make_spider()
	pickup.submerge()

	pickup._on_body_entered(spider) # direct call, same as every other test in this file

	# _on_body_entered() itself doesn't check `monitoring` (Area2D's own
	# collision system is what `monitoring` gates in real play) -- this test
	# instead documents the intended real-game behavior: monitoring=false
	# means Godot's physics server never actually calls _on_body_entered in
	# the first place, so exercising `monitoring` itself is what matters.
	assert_false(pickup.monitoring, "monitoring stays off while submerged, preventing real overlap detection")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_web_trap.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'force_destroy'`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_world_item_pickup.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'submerge'`.

- [ ] **Step 3: Write the implementation**

In `entities/web/web_trap.gd`, add a new method right after `take_web_hit()`:

```gdscript
## Destroys the trap immediately, regardless of hits_to_destroy — used by
## anything that removes a trap's tile out from under it (water flooding
## it, a compacted tile crushing it), as opposed to take_web_hit()'s
## shot-counter path. Same cleanup either way: releases any caught larva,
## leaves a torn-web visual, frees itself.
func force_destroy() -> void:
	if spent:
		return
	spent = true
	if is_instance_valid(caught_larva):
		caught_larva.queue_free()
		caught_larva = null
	_leave_torn_web()
	queue_free()
```

In `entities/items/world_item_pickup.gd`, add two new methods right after `_on_body_entered()`:

```gdscript
## Hides and disables the pickup while its tile is underwater — the item
## survives (unlike a web trap), it's just inaccessible until the water
## recedes.
func submerge() -> void:
	visible = false
	monitoring = false


func resurface() -> void:
	visible = true
	monitoring = true
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_web_trap.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_world_item_pickup.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add entities/web/web_trap.gd entities/items/world_item_pickup.gd tests/test_web_trap.gd tests/test_world_item_pickup.gd
git status # stage a stray .gd.uid if one appears
git commit -m "WebTrap.force_destroy() + WorldItemPickup.submerge()/resurface()"
```

---

### Task 2: `Level` — water tile tracking, distinct blue marker, `patch_pit_at` fix

**Files:**
- Modify: `world/level.gd`
- Test: `tests/test_level_hazard_helpers.gd` (extend)

**Interfaces:**
- Consumes: `WebTrap.force_destroy()`, `WorldItemPickup.submerge()`/`resurface()` (Task 1).
- Produces: `Level.set_water_at(tile: Vector2i, value: bool) -> void` (consumed by Task 3), `Level._water_tiles: Dictionary` (tile → `true`, readable by tests/Task 3).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_level_hazard_helpers.gd` (reusing its existing `_make_level()` helper exactly):

```gdscript
func test_set_water_at_blocks_ground_movement_like_a_pit() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_water_at(open_cell, true)
	assert_true(level.maze.is_pit(open_cell.x, open_cell.y))
	assert_true(level.is_blocked(open_cell, Level.Layer.GROUND))


func test_set_water_at_spawns_a_distinct_blue_marker_not_the_pit_marker() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_water_at(open_cell, true)
	assert_true(level._water_nodes.has(open_cell))
	assert_false(level._pit_nodes.has(open_cell), "water uses its own marker, not the brown pit one")
	var marker: Node2D = level._water_nodes[open_cell]
	assert_eq((marker as Polygon2D).color, Level.WATER_MARKER_COLOR)


func test_set_water_at_false_clears_the_block_and_frees_the_marker() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_water_at(open_cell, true)
	level.set_water_at(open_cell, false)
	assert_false(level.maze.is_pit(open_cell.x, open_cell.y))
	assert_false(level._water_nodes.has(open_cell))


func test_set_water_at_true_destroys_a_web_trap_on_that_tile() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	var trap := WebTrap.new()
	level.add_child(trap)
	trap.global_position = level._tile_centre(open_cell.x, open_cell.y)

	level.set_water_at(open_cell, true)

	assert_true(trap.spent, "flooding a tile destroys the web trap on it")


func test_set_water_at_true_submerges_an_item_on_that_tile() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	var pickup: WorldItemPickup = preload("res://entities/items/world_item_pickup.tscn").instantiate()
	level.add_child(pickup)
	pickup.global_position = level._tile_centre(open_cell.x, open_cell.y)

	level.set_water_at(open_cell, true)

	assert_false(pickup.visible, "flooding a tile submerges the item on it")
	assert_false(pickup.monitoring)


func test_set_water_at_false_resurfaces_an_item_on_that_tile() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	var pickup: WorldItemPickup = preload("res://entities/items/world_item_pickup.tscn").instantiate()
	level.add_child(pickup)
	pickup.global_position = level._tile_centre(open_cell.x, open_cell.y)
	level.set_water_at(open_cell, true)

	level.set_water_at(open_cell, false)

	assert_true(pickup.visible, "draining a tile resurfaces the item on it")
	assert_true(pickup.monitoring)


func test_patch_pit_at_on_a_flooded_tile_clears_water_state_too() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_water_at(open_cell, true)

	level.patch_pit_at(open_cell)

	assert_false(level.maze.is_pit(open_cell.x, open_cell.y))
	assert_false(level._water_nodes.has(open_cell), "patching a flooded tile also clears its blue marker")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_hazard_helpers.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'set_water_at'`.

- [ ] **Step 3: Write the implementation**

In `world/level.gd`, add new instance vars near `var _pit_nodes: Dictionary = {}`:

```gdscript
## Water tile tracking (environment tiles rework): parallel to _pit_nodes,
## kept entirely separate so a natural pit and a flooded tile can look
## different even though both block ground movement via the same
## MazeData._pits overlay underneath.
var _water_tiles: Dictionary = {}
var _water_nodes: Dictionary = {}
const WATER_MARKER_COLOR := Color(0.15, 0.45, 0.75, 0.75)
```

Add new methods right after `_spawn_pit_marker()`:

```gdscript
## Flag/clear a water tile (environment tiles rework). Touches
## maze.set_pit() directly (not via set_pit_at()) so water gets its own
## blue marker instead of set_pit_at()'s brown pit one — water and a
## natural pit share the same underlying ground-block flag but never the
## same visual. Flooding a tile destroys any WebTrap on it and submerges
## any WorldItemPickup on it (survives, unlike the trap); draining
## resurfaces the item.
func set_water_at(tile: Vector2i, value: bool) -> void:
	if maze == null:
		return
	maze.set_pit(tile.x, tile.y, value)
	if value:
		_water_tiles[tile] = true
		if not _water_nodes.has(tile):
			_water_nodes[tile] = _spawn_water_marker(tile)
		_drown_traps_at(tile)
		_submerge_items_at(tile)
	else:
		_water_tiles.erase(tile)
		var marker = _water_nodes.get(tile)
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
		_water_nodes.erase(tile)
		_resurface_items_at(tile)


func _spawn_water_marker(tile: Vector2i) -> Node2D:
	var half := TILE_SIZE * 0.5
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])
	poly.color = WATER_MARKER_COLOR
	poly.position = _tile_centre(tile.x, tile.y)
	add_child(poly)
	return poly


func _drown_traps_at(tile: Vector2i) -> void:
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("traps"):
		var trap := node as WebTrap
		if trap != null and tile_of(trap.global_position) == tile:
			trap.force_destroy()


func _submerge_items_at(tile: Vector2i) -> void:
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("world_items"):
		var item := node as WorldItemPickup
		if item != null and tile_of(item.global_position) == tile:
			item.submerge()


func _resurface_items_at(tile: Vector2i) -> void:
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("world_items"):
		var item := node as WorldItemPickup
		if item != null and tile_of(item.global_position) == tile:
			item.resurface()
```

Replace `patch_pit_at()`:

```gdscript
## BlockadeSkill: patch a hazard tile (pit or water) for ground traversal by
## placing a blockade on it. Routes through set_water_at() for a flooded
## tile so its blue marker and water-tile tracking are cleared too, not
## just the underlying block flag — otherwise a stale blue marker would be
## left floating over an already-walkable tile. No-op if `tile` is neither
## a pit nor water.
func patch_pit_at(tile: Vector2i) -> void:
	if _water_tiles.has(tile):
		set_water_at(tile, false)
	else:
		set_pit_at(tile, false)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_hazard_helpers.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Run the full suite once** (this task touches a shared file, `Level`)

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add world/level.gd tests/test_level_hazard_helpers.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Level: water tile tracking with a distinct blue marker, patch_pit_at fix"
```

---

### Task 3: `WaterIngress` — ring-based spreading fill and gradual drain

**Files:**
- Modify: `world/hazards/water_ingress.gd`
- Test: `tests/test_water_ingress.gd` (new)

**Interfaces:**
- Consumes: `Level.set_water_at()` (Task 2).
- Produces: `WaterIngress._compute_rings(maze: MazeData, origin: Vector2i) -> Array` (static), `WaterIngress._flood_ring(level: Node, tiles: Array) -> void` (static), `WaterIngress._drain_ring(level: Node, tiles: Array) -> void` (static).

- [ ] **Step 1: Write the failing tests**

Create `tests/test_water_ingress.gd`:

```gdscript
extends GutTest
## WaterIngress's ring-based spread/drain (environment tiles rework):
## _compute_rings groups tiles by Chebyshev distance from the origin so the
## flood can spread outward and drain back inward over time instead of
## stamping/vanishing instantly. _flood_ring/_drain_ring are the per-ring
## actions the real timer-scheduled trigger() calls; tested directly here
## since real SceneTreeTimer pacing isn't practically unit-testable.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_compute_rings_ring_zero_is_exactly_the_origin() -> void:
	var level := _make_level()
	var origin: Vector2i = level.maze.open_cells()[0]

	var rings := WaterIngress._compute_rings(level.maze, origin)

	assert_eq(rings[0], [origin])


func test_compute_rings_covers_up_to_flood_radius_only() -> void:
	var level := _make_level()
	var origin: Vector2i = level.maze.open_cells()[0]

	var rings := WaterIngress._compute_rings(level.maze, origin)

	assert_eq(rings.size(), WaterIngress.FLOOD_RADIUS + 1)


func test_compute_rings_excludes_walls_and_boundary_tiles() -> void:
	var level := _make_level()
	var origin: Vector2i = level.maze.open_cells()[0]

	var rings := WaterIngress._compute_rings(level.maze, origin)

	for ring in rings:
		for tile in ring:
			assert_true(level.maze.is_open(tile.x, tile.y), "every ring tile must be open ground")
			assert_false(level.maze.is_boundary(tile.x, tile.y), "boundary tiles are never included")


func test_flood_ring_floods_every_tile_in_the_ring() -> void:
	var level := _make_level()
	var tiles: Array = [level.maze.open_cells()[0], level.maze.open_cells()[1]]

	WaterIngress._flood_ring(level, tiles)

	for tile in tiles:
		assert_true(level.maze.is_pit(tile.x, tile.y))
		assert_true(level._water_nodes.has(tile))


func test_drain_ring_drains_every_tile_in_the_ring() -> void:
	var level := _make_level()
	var tiles: Array = [level.maze.open_cells()[0], level.maze.open_cells()[1]]
	WaterIngress._flood_ring(level, tiles)

	WaterIngress._drain_ring(level, tiles)

	for tile in tiles:
		assert_false(level.maze.is_pit(tile.x, tile.y))
		assert_false(level._water_nodes.has(tile))


func test_flood_ring_is_a_noop_on_a_freed_level() -> void:
	var level := preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	var tiles: Array = [level.maze.open_cells()[0]]
	level.queue_free()
	await get_tree().process_frame

	WaterIngress._flood_ring(level, tiles) # must not error on a freed level
	assert_true(true, "reached this point without erroring")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_water_ingress.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function '_compute_rings'`.

- [ ] **Step 3: Write the implementation**

Replace the whole of `world/hazards/water_ingress.gd` with:

```gdscript
class_name WaterIngress
extends HazardEvent
## Floods a spreading patch of open ground tiles ring-by-ring (environment
## tiles rework), rather than one instant fixed-radius stamp: ring 0 (the
## origin) floods immediately, ring 1 RING_STEP seconds later, ring 2
## another RING_STEP after that, and so on out to FLOOD_RADIUS. Draining is
## the mirror — the outermost ring drains first, the origin drains last —
## so the flood reads as spreading out from, then receding back into, its
## source. Each ring's ground-block/marker/web/item side effects go through
## Level.set_water_at(), which shares MazeData's pit overlay for blocking
## (a flood and a pit both mean "ground movement blocked here, ceiling
## unaffected" — see CeilingData) but tracks its own distinct blue marker,
## separate from a natural pit's brown one. Never touches boundary tiles
## (guardrail), so the border can't be "washed away".

const FLOOD_RADIUS := 2
const FLOOD_DURATION := 12.0
## Seconds between each ring flooding/draining — a first-pass pacing
## number, not a balance decision. Tune during playtest.
const RING_STEP := 0.4


func trigger(level: Node) -> void:
	if level == null or level.maze == null:
		return
	var cells: Array = level.maze.open_cells()
	if cells.is_empty():
		return
	cells.shuffle()
	var origin: Vector2i = cells[0]
	var rings := _compute_rings(level.maze, origin)
	var tree := level.get_tree()
	if tree == null:
		return
	var full_flood_time := float(FLOOD_RADIUS) * RING_STEP
	for k in rings.size():
		var ring_tiles: Array = rings[k]
		if ring_tiles.is_empty():
			continue
		tree.create_timer(float(k) * RING_STEP).timeout.connect(
			func() -> void: _flood_ring(level, ring_tiles))
		var drain_delay: float = full_flood_time + FLOOD_DURATION + float(FLOOD_RADIUS - k) * RING_STEP
		tree.create_timer(drain_delay).timeout.connect(
			func() -> void: _drain_ring(level, ring_tiles))
	EventBus.hazard_triggered.emit("water_ingress")


## Tiles at each Chebyshev distance 0..FLOOD_RADIUS from `origin` that are
## open and non-boundary — rings[k] is the ring at distance k. A plain,
## timer-free function so ring computation is unit-testable without
## waiting on real timers.
static func _compute_rings(maze: MazeData, origin: Vector2i) -> Array:
	var rings: Array = []
	for _k in range(FLOOD_RADIUS + 1):
		rings.append([])
	for dx in range(-FLOOD_RADIUS, FLOOD_RADIUS + 1):
		for dy in range(-FLOOD_RADIUS, FLOOD_RADIUS + 1):
			var tile := origin + Vector2i(dx, dy)
			if not maze.is_open(tile.x, tile.y) or maze.is_boundary(tile.x, tile.y):
				continue
			var dist := maxi(absi(dx), absi(dy))
			rings[dist].append(tile)
	return rings


static func _flood_ring(level: Node, tiles: Array) -> void:
	if level == null or not is_instance_valid(level):
		return
	for tile in tiles:
		level.set_water_at(tile, true)


static func _drain_ring(level: Node, tiles: Array) -> void:
	if level == null or not is_instance_valid(level):
		return
	for tile in tiles:
		level.set_water_at(tile, false)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_water_ingress.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add world/hazards/water_ingress.gd tests/test_water_ingress.gd
git status # stage a stray .gd.uid if one appears
git commit -m "WaterIngress: ring-based spreading fill and gradual drain"
```

---

### Task 4: Compaction destroys occupants + `CombatFx.spawn_collapse_dust()`

**Files:**
- Modify: `world/level.gd`
- Modify: `components/combat_fx.gd`
- Test: `tests/test_level_hazard_helpers.gd` (extend)
- Test: `tests/test_combat_fx.gd` (extend)
- Test: `tests/test_seismic_compaction.gd` (new)

**Interfaces:**
- Consumes: `WebTrap.force_destroy()` (Task 1).
- Produces: `Level._destroy_occupants_at(tile: Vector2i) -> void` (private), `CombatFx.spawn_collapse_dust(holder: Node, world_position: Vector2) -> void`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_combat_fx.gd`:

```gdscript
func test_spawn_collapse_dust_adds_a_node_under_holder() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)

	CombatFx.spawn_collapse_dust(holder, Vector2(100, 100))

	assert_eq(holder.get_child_count(), 1, "spawns exactly one dust node")


func test_spawn_collapse_dust_frees_itself_after_its_tween() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)

	CombatFx.spawn_collapse_dust(holder, Vector2(100, 100))
	var dust: Node = holder.get_child(0)

	await get_tree().create_timer(0.4).timeout

	assert_true(dust.is_queued_for_deletion(), "the dust cloud frees itself once its tween finishes")
```

Append to `tests/test_level_hazard_helpers.gd`:

```gdscript
func test_collapse_tile_at_destroys_a_larva_on_the_tile() -> void:
	var level := _make_level()
	var interior_cell := Vector2i(3, 3)
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	level.add_child(larva)
	larva.global_position = level._tile_centre(interior_cell.x, interior_cell.y)

	level.collapse_tile_at(interior_cell)

	assert_true(larva.is_queued_for_deletion(), "a larva on a collapsed tile is destroyed")


func test_collapse_tile_at_destroys_a_web_trap_on_the_tile() -> void:
	var level := _make_level()
	var interior_cell := Vector2i(3, 3)
	var trap := WebTrap.new()
	level.add_child(trap)
	trap.global_position = level._tile_centre(interior_cell.x, interior_cell.y)

	level.collapse_tile_at(interior_cell)

	assert_true(trap.spent, "a web trap on a collapsed tile is destroyed")


func test_collapse_tile_at_destroys_an_item_on_the_tile_permanently() -> void:
	var level := _make_level()
	var interior_cell := Vector2i(3, 3)
	var pickup: WorldItemPickup = preload("res://entities/items/world_item_pickup.tscn").instantiate()
	level.add_child(pickup)
	pickup.global_position = level._tile_centre(interior_cell.x, interior_cell.y)

	level.collapse_tile_at(interior_cell)

	assert_true(pickup.is_queued_for_deletion(),
		"unlike water (which submerges then restores), compaction destroys an item outright")
```

Create `tests/test_seismic_compaction.gd`:

```gdscript
extends GutTest
## Seismic Compaction's collapse pass (environment tiles rework): a
## spider-occupied tile is still never a collapse candidate (unchanged
## eligibility check) -- Level.collapse_tile_at() itself is what now
## destroys any larva/web/item on an eligible tile, covered directly in
## tests/test_level_hazard_helpers.gd.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_collapse_candidates_exclude_a_spider_occupied_tile() -> void:
	var level := _make_level()
	var interior_cell := Vector2i(3, 3)
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	level.add_child(spider)
	spider.global_position = level._tile_centre(interior_cell.x, interior_cell.y)

	var compaction := SeismicCompaction.new()
	assert_true(compaction._is_occupied(level, interior_cell),
		"a spider-occupied tile is still excluded from collapse candidates")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_combat_fx.gd 2>&1`
Expected: FAIL — `Invalid call. Nonexistent function 'spawn_collapse_dust'`.

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_hazard_helpers.gd 2>&1`
Expected: FAIL — the three new `test_collapse_tile_at_destroys_*` tests fail (nothing on the tile is destroyed today).

- [ ] **Step 3: Write the implementation**

In `components/combat_fx.gd`, add a new static method after `spawn_slash()`:

```gdscript
## A brief expanding, fading dust cloud at `world_position` — the visual
## cue for a tile about to be crushed by Seismic Compaction. Purely
## cosmetic, frees itself; never touches game state.
static func spawn_collapse_dust(holder: Node, world_position: Vector2) -> void:
	var dust := Polygon2D.new()
	var half := 20.0
	dust.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])
	dust.color = Color(0.4, 0.35, 0.3, 0.8)
	dust.position = world_position
	holder.add_child(dust)
	var tween := dust.create_tween()
	tween.set_parallel(true)
	tween.tween_property(dust, "scale", Vector2(1.6, 1.6), 0.3)
	tween.tween_property(dust, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(dust.queue_free)
```

In `world/level.gd`, replace `collapse_tile_at()`:

```gdscript
## Inverse of dev_remove_wall_at: collapses an open, currently-unoccupied tile
## back into a wall (Seismic Compaction's collapse pass). No-op out of
## bounds, on a boundary tile (guardrail — re-checked defensively even though
## callers should already filter via MazeData.is_boundary), or if the tile is
## already a wall. Destroys whatever's on the tile first (environment tiles
## rework) and plays a brief cosmetic dust cue.
func collapse_tile_at(tile: Vector2i) -> bool:
	if maze == null or maze.is_boundary(tile.x, tile.y):
		return false
	if not (tile.x >= 0 and tile.x < maze.width and tile.y >= 0 and tile.y < maze.height):
		return false
	if not maze.is_open(tile.x, tile.y):
		return false
	_destroy_occupants_at(tile)
	CombatFx.spawn_collapse_dust(self, _tile_centre(tile.x, tile.y))
	maze.set_wall(tile.x, tile.y)
	_spawn_wall_node(tile)
	if _astar != null:
		_astar.set_point_solid(tile, true)
	_renderer.queue_redraw()
	return true


## A tile about to become a wall permanently destroys whatever's on it —
## larvae, web traps (via the same force_destroy() water uses), and items
## (queue_free directly: unlike water, compaction never restores anything —
## see set_water_at()'s own doc comment for the deliberate contrast).
## Spider occupancy is unaffected — the caller (SeismicCompaction) already
## excludes spider-occupied tiles from its collapse candidates entirely
## (unchanged), so a living spider is never at risk here.
func _destroy_occupants_at(tile: Vector2i) -> void:
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("larvae"):
		if tile_of((node as Node2D).global_position) == tile:
			node.queue_free()
	for node in get_tree().get_nodes_in_group("traps"):
		var trap := node as WebTrap
		if trap != null and tile_of(trap.global_position) == tile:
			trap.force_destroy()
	for node in get_tree().get_nodes_in_group("world_items"):
		if tile_of((node as Node2D).global_position) == tile:
			node.queue_free()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_combat_fx.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_level_hazard_helpers.gd 2>&1`
Expected: `All tests passed!`

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit -gselect=test_seismic_compaction.gd 2>&1`
Expected: `All tests passed!`

- [ ] **Step 5: Run the full suite once**

Run: `~/.local/bin/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit 2>&1`
Expected: `All tests passed!`

- [ ] **Step 6: Import check**

Run: `~/.local/bin/godot --headless --path . --import 2>&1 | grep -i error`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add world/level.gd components/combat_fx.gd tests/test_level_hazard_helpers.gd tests/test_combat_fx.gd tests/test_seismic_compaction.gd
git status # stage a stray .gd.uid if one appears
git commit -m "Compaction destroys larvae/web traps/items on a collapsed tile; adds a dust cue"
```

---

## Final whole-branch pass (not a numbered task — do this after Task 4)

- Run the full GUT suite once more end-to-end.
- Manual/windowed playtest pass specifically for: water visibly spreads outward ring-by-ring rather than popping in all at once, is blue and reads as distinct from a natural pit's brown marker, destroys a web trap sitting in its path, submerges an item (which reappears once the water there recedes), and drains ring-by-ring rather than vanishing all at once; Seismic Compaction visibly plays the dust cue and permanently removes a larva/trap/item caught under it. Real timer pacing (`RING_STEP`, `FLOOD_DURATION`) is not practically unit-testable — this is exactly the category of thing GUT can't catch (see memory: godot-validation-workflow) — don't skip it even though every automated test is green.
