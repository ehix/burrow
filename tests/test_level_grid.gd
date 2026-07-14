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


func test_dev_remove_wall_floods_the_new_opening_if_adjacent_to_water() -> void:
	var level := _make_level()
	level.build()
	# Find a wall tile with an open, non-boundary neighbor to flood.
	var target := Vector2i(-1, -1)
	var wet_neighbor := Vector2i(-1, -1)
	for y in range(1, level.maze.height - 1):
		for x in range(1, level.maze.width - 1):
			if level.maze.is_open(x, y):
				continue
			var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
			for dir in dirs:
				var neighbor := Vector2i(x, y) + dir
				if level.maze.is_open(neighbor.x, neighbor.y) and not level.is_boundary(neighbor):
					target = Vector2i(x, y)
					wet_neighbor = neighbor
					break
			if target != Vector2i(-1, -1):
				break
		if target != Vector2i(-1, -1):
			break
	assert_ne(target, Vector2i(-1, -1), "found a wall tile with an open neighbor to flood")
	level.set_water_at(wet_neighbor, true)

	level.dev_remove_wall_at(target)

	assert_true(level.is_water_at(target),
		"a wall carved open right next to an active flood is flooded too, not left dry in the middle of it")


func test_dev_remove_wall_does_not_flood_a_new_opening_away_from_water() -> void:
	var level := _make_level()
	level.build()
	assert_false(level.maze.is_open(0, 0))

	level.dev_remove_wall_at(Vector2i(0, 0))

	assert_false(level.is_water_at(Vector2i(0, 0)), "no flood nearby -- stays dry")
