extends GutTest
## Level's tile<->world conversions round-trip on tile centres.
## `level` is typed as Level (not the inferred Node from instantiate()) so the
## Level methods resolve at parse time.

const LevelScene := preload("res://world/level.tscn")


func _make_level() -> Level:
	var level: Level = LevelScene.instantiate()
	add_child_autofree(level)
	return level


func test_tile_of_and_centre_of_round_trip() -> void:
	var level := _make_level()
	# centre_of a tile, then tile_of that point, returns the same tile.
	for tile in [Vector2i(1, 1), Vector2i(3, 5), Vector2i(8, 8)]:
		var centre := level.centre_of(tile)
		assert_eq(level.tile_of(centre), tile, "round-trips tile %s" % tile)


func test_centre_is_tile_middle() -> void:
	var level := _make_level()
	assert_eq(level.centre_of(Vector2i(0, 0)), Vector2(24, 24))


func test_dev_remove_wall_carves_the_border_open() -> void:
	var level := _make_level()
	level.build()
	assert_false(level.maze.is_open(0, 0), "the border is a wall")
	var removed := level.dev_remove_wall_at(Vector2i(0, 0))
	assert_true(removed)
	assert_true(level.maze.is_open(0, 0), "the tile is carved into floor")
	assert_false(level._astar.is_point_solid(Vector2i(0, 0)), "the AStar grid is updated too")


func test_dev_remove_wall_on_open_tile_is_a_noop() -> void:
	var level := _make_level()
	level.build()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	var removed := level.dev_remove_wall_at(open_cell)
	assert_false(removed, "an already-open tile has nothing to remove")


func test_dev_remove_wall_out_of_bounds_is_a_noop() -> void:
	var level := _make_level()
	level.build()
	assert_false(level.dev_remove_wall_at(Vector2i(-1, -1)))


## Finds an open, non-boundary cell (a plausible flood origin) with a wall
## tile somewhere within WaterIngress.FLOOD_RADIUS of it -- returns
## [origin, wall_tile], or [] if none exists in this maze.
func _find_origin_with_a_wall_in_radius(level: Level) -> Array:
	for cell in level.maze.open_cells():
		if level.is_boundary(cell):
			continue
		for dx in range(-WaterIngress.FLOOD_RADIUS, WaterIngress.FLOOD_RADIUS + 1):
			for dy in range(-WaterIngress.FLOOD_RADIUS, WaterIngress.FLOOD_RADIUS + 1):
				var candidate: Vector2i = cell + Vector2i(dx, dy)
				if level.is_boundary(candidate) or level.maze.is_open(candidate.x, candidate.y):
					continue
				return [cell, candidate]
	return []


func test_dev_remove_wall_floods_a_new_opening_within_an_active_floods_radius() -> void:
	var level := _make_level()
	level.build()
	var found := _find_origin_with_a_wall_in_radius(level)
	assert_eq(found.size(), 2, "found an origin with a wall tile inside its flood radius")
	var flood := WaterIngress.ActiveFlood.new(found[0])
	level.register_active_flood(flood)

	level.dev_remove_wall_at(found[1])

	assert_true(level.is_water_at(found[1]),
		"a wall carved open within an active flood's radius is flooded too, not left dry in the middle of it")


func test_dev_remove_wall_does_not_flood_an_opening_outside_the_floods_radius() -> void:
	var level := _make_level()
	level.build()
	var origin: Vector2i = level.maze.open_cells()[0]
	level.register_active_flood(WaterIngress.ActiveFlood.new(origin))
	var target := Vector2i(-1, -1)
	for y in range(1, level.maze.height - 1):
		for x in range(1, level.maze.width - 1):
			if level.maze.is_open(x, y):
				continue
			if maxi(absi(x - origin.x), absi(y - origin.y)) > WaterIngress.FLOOD_RADIUS:
				target = Vector2i(x, y)
				break
		if target != Vector2i(-1, -1):
			break
	assert_ne(target, Vector2i(-1, -1), "found a wall tile outside the flood's radius")

	level.dev_remove_wall_at(target)

	assert_false(level.is_water_at(target), "outside the flood's radius -- stays dry")


func test_dev_remove_wall_does_not_flood_once_the_floods_ring_already_drained() -> void:
	var level := _make_level()
	level.build()
	var found := _find_origin_with_a_wall_in_radius(level)
	assert_eq(found.size(), 2)
	var flood := WaterIngress.ActiveFlood.new(found[0])
	flood.started_at_msec -= 60000 # long enough ago that every ring has already drained
	level.register_active_flood(flood)

	level.dev_remove_wall_at(found[1])

	assert_false(level.is_water_at(found[1]),
		"the flood already receded past here -- stays dry, doesn't get permanently re-flooded")
