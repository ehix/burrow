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
		if k == 0:
			_flood_ring(level, ring_tiles)
		else:
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


## `level` is deliberately untyped (not `Node`): a strictly-typed Node
## parameter fails Godot's runtime type check when passed a freed object,
## raising a script error before the function body (and its
## is_instance_valid guard) ever runs. Leaving it untyped lets the guard
## below do its job so a freed level is a genuine no-op.
static func _flood_ring(level, tiles: Array) -> void:
	if level == null or not is_instance_valid(level):
		return
	for tile in tiles:
		level.set_water_at(tile, true)


static func _drain_ring(level, tiles: Array) -> void:
	if level == null or not is_instance_valid(level):
		return
	for tile in tiles:
		level.set_water_at(tile, false)
