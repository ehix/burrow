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


## trigger()'s ring timers used to capture `level` itself inside their
## func() -> void: closures. If the level was freed before a timer fired --
## e.g. the round ending mid-flood, well within FLOOD_DURATION's 12s -- the
## GDScript engine detects the freed Object held in that typed capture slot
## and logs "Lambda capture at index 0 was freed. Passed 'null' instead."
## (gdscript_lambda_callable.cpp) the instant the Callable is invoked,
## before _flood_ring()/_drain_ring()'s own is_instance_valid() guard ever
## runs -- confirmed via a standalone headless repro (a Node captured
## directly in a timer callback logs this error once freed; the same
## scenario with an instance ID captured instead does not). trigger() now
## captures level.get_instance_id() and resolves it back through
## _resolve_level() inside each closure instead, so there's nothing left
## for the engine to find freed at invocation time -- this covers that
## resolver in isolation.
func test_resolve_level_returns_the_live_level_for_a_valid_id() -> void:
	var level := _make_level()

	var resolved := WaterIngress._resolve_level(level.get_instance_id())

	assert_eq(resolved, level)


func test_resolve_level_returns_null_for_a_freed_levels_id() -> void:
	var level := preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	var id := level.get_instance_id()
	level.queue_free()
	await get_tree().process_frame

	var resolved := WaterIngress._resolve_level(id)

	assert_eq(resolved, null)
