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
