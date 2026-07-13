# Environment Tiles Rework — Design

## Context

Sub-project G of the playtest roadmap (see memory: burrow-playtest-roadmap).
Scope per the roadmap: "Real distinct water tile (blue, spreading fill,
destroys webs but not items, item restore-on-drain), compaction that
actually destroys stuff + animates."

**Autonomy note:** the user delegated the full pipeline overnight (see
memory: burrow-user-delegates-full-autonomy) and is asleep for this
sub-project's brainstorm — there was no live design conversation the way
sub-project F got. Every design decision below is a solo judgment call,
grounded in the actual current codebase (read in full before designing, not
guessed at) and kept as additive/minimal as the roadmap wording allows. All
are flagged inline; nothing here overrides an explicit prior instruction —
this is filling an entirely unscoped gap, the situation the autonomy
agreement is meant to cover.

Scope: `world/level.gd`, `world/hazards/water_ingress.gd`,
`world/hazards/seismic_compaction.gd`, `entities/web/web_trap.gd`,
`entities/items/world_item_pickup.gd`, `components/combat_fx.gd`, and their
tests.

## Current state

- **Water has no identity of its own.** `WaterIngress.trigger()`
  (`world/hazards/water_ingress.gd:14-32`) is a one-shot, fixed-radius
  square stamp: it calls `Level.set_pit_at(tile, true)` for every open tile
  within `FLOOD_RADIUS=2` (Chebyshev distance) of a random origin, then a
  single `12.0`s timer flips them all back off at once
  (`_recede`, lines 35-39). Water *is* `MazeData`'s pit overlay — same
  `_pits` dictionary a permanent natural pit uses
  (`world/maze/maze_data.gd:15,63-81`), same brown `Polygon2D` marker
  (`Level._spawn_pit_marker`, `world/level.gd:479-488`,
  `Color(0.15, 0.08, 0.05, 0.85)`). No spread animation, no distinct color,
  no web/item interaction of any kind.
- **Compaction exists but doesn't destroy anything.**
  `SeismicCompaction._collapse_random_floors`
  (`world/hazards/seismic_compaction.gd:32-49`) picks `COLLAPSE_COUNT=3`
  random open tiles, skipping only tiles a **spider** currently occupies
  (`_is_occupied`, lines 43-49 — checks group `"spiders"` only), and calls
  `Level.collapse_tile_at` (`world/level.gd:510-522`), which just flips the
  tile to a wall (`maze.set_wall`, spawns collision/occluder, marks the
  AStar point solid, redraws). Any larva, web trap, or item already
  standing on that tile is left exactly where it was — now inside solid
  wall geometry, neither destroyed nor visibly acknowledged. No animation
  of any kind plays.
- **Items** (`entities/items/world_item_pickup.gd`) are a plain `Area2D`
  in group `"world_items"` (line 22), freed only via a successful
  `InventoryComponent.try_pickup()` (lines 31-38). Zero tile/hazard
  awareness; no existing "submerge"/"restore" concept anywhere in the
  codebase.
- **Web traps** (`entities/web/web_trap.gd`) are destroyed today only via
  `take_web_hit()` (lines 108-118, a shot-counter reaching
  `hits_to_destroy`), which frees any caught larva, spawns a torn-web
  visual (`_leave_torn_web`, lines 121-127), and frees itself. No path to
  destroy a trap for any other reason exists yet.
- **`MazeRenderer`** only branches floor color on the ceiling/plane
  rework's `_active_plane` (`world/maze/maze_renderer.gd:40-48`); it never
  reads `maze.is_pit()`. The *only* pit/water visual today is the
  standalone marker node `Level.set_pit_at` spawns per-tile — not part of
  the batched tile-grid draw.

## Design

### 1. Water becomes its own tracked concept, layered on top of the pit overlay

Natural pits (seeded permanently at map build,
`Level._seed_natural_pits` per the earlier ceiling/plane work) and water
must now look and behave differently, even though both still block ground
movement identically (bypassed on the ceiling plane — unchanged,
`CeilingData` still never checks pits). `Level` gains a second, parallel
tracking dictionary and marker set, entirely separate from the existing
pit ones:

```gdscript
var _water_tiles: Dictionary = {}
var _water_nodes: Dictionary = {}
const WATER_MARKER_COLOR := Color(0.15, 0.45, 0.75, 0.75)
```

`set_water_at(tile: Vector2i, value: bool) -> void` is the one entry point
`WaterIngress` uses (mirroring `set_pit_at`'s own role for natural pits):

- Touches `maze.set_pit(tile.x, tile.y, value)` **directly** (not via
  `set_pit_at`) — water needs the same ground-blocking side effect a pit
  has, but must manage its *own* marker (blue, not brown) rather than
  triggering `set_pit_at`'s brown-marker bookkeeping, which would stack
  two markers on one tile.
- On flood (`value == true`): spawns the blue marker if not already
  present, then finds and destroys any `WebTrap` at that tile (see §2) and
  submerges any `WorldItemPickup` at that tile (see §3).
- On drain (`value == false`): frees the blue marker, then resurfaces any
  submerged item at that tile.

**Judgment call — `patch_pit_at` (Blockade's "fill in a pit" skill hook,
`world/level.gd:493-494`).** A Blockade placed on a currently-flooded tile
must clear the water state too, not just the underlying block, or it would
leave a stale blue marker floating over an already-walkable tile.
`patch_pit_at` now checks `_water_tiles` first and routes through
`set_water_at(tile, false)` instead of `set_pit_at(tile, false)` when the
tile is water — same one-line "patch it" behavior from the skill's
perspective, correct cleanup either way.

### 2. Water destroys web traps

`WebTrap` gains a new public method, deliberately **not** named after
water specifically — sub-project's compaction rework (§4) needs the exact
same "destroy this trap outright, right now" behavior for an unrelated
reason (a tile being crushed into a wall), so one shared method serves
both:

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

`Level.set_water_at(tile, true)` finds any `WebTrap` in group `"traps"`
whose tile matches and calls `force_destroy()` on it.

### 3. Water spares items — submerge on flood, restore on drain

`WorldItemPickup` gains two small methods:

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

`Level.set_water_at(tile, true)` submerges any `WorldItemPickup` at that
tile; `set_water_at(tile, false)` resurfaces it. This is the roadmap's
"item restore-on-drain" — items are never destroyed by water, only
temporarily hidden and unpickupable.

**Judgment call — items vs. compaction.** By contrast, §4's compaction
`queue_free()`s any item on a tile it crushes, permanently. This asymmetry
is deliberate and central to the roadmap's own wording: water is a
temporary, reversible hazard ("restore-on-drain"); compaction is
permanent ("actually destroys stuff"). Same entity, two hazards, two
different fates — not an inconsistency to reconcile.

### 4. Water spreads and drains ring-by-ring instead of stamping/vanishing instantly

`WaterIngress` computes concentric Chebyshev-distance rings around the
same random origin tile (ring 0 = the origin itself, ring 1 = the 8
tiles at distance 1, ring 2 = the 16 at distance 2, for `FLOOD_RADIUS=2`
unchanged) and schedules each ring's flood and, later, drain via
`get_tree().create_timer()`, instead of one instant stamp and one instant
clear:

```gdscript
const FLOOD_RADIUS := 2
const FLOOD_DURATION := 12.0
## Seconds between each ring flooding/draining — a FLOOD_RADIUS=2 flood
## finishes spreading in 2*RING_STEP seconds and finishes draining in
## another (FLOOD_RADIUS+1)*RING_STEP seconds after FLOOD_DURATION elapses.
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
		var drain_delay := full_flood_time + FLOOD_DURATION + float(FLOOD_RADIUS - k) * RING_STEP
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

Drain order is the mirror of flood order (outermost ring drains first,
origin drains last) — reads as water receding back toward its source
rather than the whole patch vanishing/appearing at once. `RING_STEP=0.4`s
is a first-pass pacing number, not a balance decision — tune during
playtest.

### 5. Compaction destroys occupants and animates before solidifying

`Level.collapse_tile_at` gains a destroy pass and a brief visual cue,
inserted before the existing wall-solidify logic (unchanged):

```gdscript
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
## larvae, web traps (via the same force_destroy() water uses, §2), and
## items (queue_free directly: unlike water, compaction never restores
## anything, §3's judgment call). Spider occupancy is unaffected — the
## caller (SeismicCompaction) already excludes spider-occupied tiles from
## its collapse candidates entirely (unchanged), so a living spider is
## never at risk here.
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

`CombatFx` (the existing home for shared, stateless visual "juice" —
`flash`/`shunt`/`spawn_slash`) gains a new static helper:

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

**Judgment call — animation plays *before* the tile solidifies, not
during/after.** The dust cloud and the wall's actual appearance are both
triggered in the same `collapse_tile_at()` call (no delay between them) —
a genuinely staggered "crumble, then solidify a beat later" sequence would
need to delay `maze.set_wall`/`_spawn_wall_node` until the dust tween
finishes, which risks a spider walking into the not-yet-solid tile during
that window (a real gameplay inconsistency, not just a visual one). Kept
simple: the wall is authoritative and instant, exactly as it already is
today; the dust is a same-instant cosmetic overlay on top, not a
gameplay-blocking sequence.

## Testing

- `tests/test_web_trap.gd` (or wherever `WebTrap` is covered): `force_destroy()`
  frees the trap, releases any caught larva, and leaves a torn-web visual,
  independent of `hits_to_destroy`/`web_hits` — including when called with
  zero prior hits.
- `tests/test_world_item_pickup.gd` (new, or extend existing coverage):
  `submerge()` sets `visible = false`/`monitoring = false`; `resurface()`
  restores both; a submerged item's `_on_body_entered` never fires (since
  `monitoring` is off) even if a spider walks through its collision area.
- Extend whichever `Level` test file covers pit/marker wiring: `set_water_at(tile, true)`
  blocks ground movement (via `maze.is_pit`) exactly like `set_pit_at`,
  spawns a distinct blue marker (not the brown pit one), destroys a
  `WebTrap` at that tile, and submerges a `WorldItemPickup` at that tile;
  `set_water_at(tile, false)` frees the marker and resurfaces the item;
  `patch_pit_at` on a flooded tile clears water state (not just the
  underlying pit flag) and frees the blue marker.
- `tests/test_water_ingress.gd` (new): `_compute_rings()` returns the
  correct tile sets per ring for a known maze/origin (ring 0 is exactly
  the origin, ring `k` is exactly the Chebyshev-distance-`k` open,
  non-boundary tiles); `_flood_ring()`/`_drain_ring()` call
  `Level.set_water_at()` with the right tiles and right boolean.
  Timer-scheduling itself (the real spread/drain pacing) is not
  practically unit-testable without driving real `SceneTreeTimer`s — covered
  by the manual playtest pass instead (same category of gap the
  Hatchlings/VFX round's Sense rework hit: see memory
  godot-validation-workflow).
- Extend `tests/test_seismic_compaction.gd` (or create it if compaction has
  no dedicated test file yet — check first): `collapse_tile_at()` destroys
  a larva/trap/item present on the collapsed tile; a spider-occupied tile
  is still skipped entirely by `SeismicCompaction._collapse_random_floors`'s
  existing `_is_occupied` check (unchanged — confirm with a regression
  test, don't just assume).
- `tests/test_combat_fx.gd` (or wherever `CombatFx` is covered): extend for
  `spawn_collapse_dust()` — spawns a node, frees itself after its tween
  completes (can be asserted via `await`/a short `process_frame` wait
  pattern matching this file's existing style for `flash`/`shunt`).
- Headless validation per the existing workflow: import check, then a
  throwaway scene run. No shader touched this round, so the
  shader-compile gap from the Hatchlings/VFX round doesn't apply here.

## Out of scope

- Any change to natural (permanent) pits' visual or behavior — they stay
  exactly as they are today (brown marker, static, no web/item
  interaction). Only water gets the new treatment.
- A gradual/animated compaction sequence that delays wall solidification
  until after the dust effect finishes (see §5's judgment call) — the wall
  is instant, the dust is a same-instant cosmetic overlay.
- Rebalancing `FLOOD_RADIUS`/`FLOOD_DURATION`/`COLLAPSE_COUNT`/hazard
  trigger intervals — only `RING_STEP` is new, and it's explicitly called
  out as a first-pass pacing number, not a tuned balance decision.
- Any MazeRenderer-level tile-grid rendering change — water's visual stays
  a standalone marker node (matching the existing pit marker's own
  architecture), not a batched draw-time tile color.
- Sub-project H (Centipede entity) — separate sub-project, next in the
  roadmap sequence; the Centipede's stated "water-avoidance pathing" will
  need to read `_water_tiles`/`maze.is_pit()` when that sub-project is
  built, but no Centipede code exists yet to wire that into.
