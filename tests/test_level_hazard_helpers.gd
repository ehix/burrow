extends GutTest
## Level's new hazard/plane-support helpers (design §1 and §7): is_boundary,
## is_blocked across both planes, patch_pit_at, and collapse_tile_at as the
## exact inverse of dev_remove_wall_at.


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_is_boundary_matches_maze_data() -> void:
	var level := _make_level()
	assert_true(level.is_boundary(Vector2i(0, 0)))
	assert_false(level.is_boundary(Vector2i(1, 1)))


func test_is_blocked_ground_respects_pits() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	assert_false(level.is_blocked(open_cell, Level.Layer.GROUND))
	level.maze.set_pit(open_cell.x, open_cell.y, true)
	assert_true(level.is_blocked(open_cell, Level.Layer.GROUND))


func test_is_blocked_ceiling_ignores_pits() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.maze.set_pit(open_cell.x, open_cell.y, true)
	assert_false(level.is_blocked(open_cell, Level.Layer.CEILING),
		"the ceiling passes over a pit that blocks the ground")


func test_patch_pit_at_clears_the_flag() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.maze.set_pit(open_cell.x, open_cell.y, true)
	level.patch_pit_at(open_cell)
	assert_false(level.maze.is_pit(open_cell.x, open_cell.y))


func test_collapse_tile_at_is_inverse_of_dev_remove_wall_at() -> void:
	var level := _make_level()
	var removed := level.dev_remove_wall_at(Vector2i(0, 0))
	assert_true(removed)
	assert_true(level.maze.is_open(0, 0))

	# collapse_tile_at itself refuses a boundary tile (guardrail), so exercise
	# the round trip on a known-interior cell centre instead (odd/odd tiles
	# are always carved open — see test_cell_centres_are_open).
	var interior_cell := Vector2i(3, 3)
	assert_true(level.maze.is_open(interior_cell.x, interior_cell.y))
	assert_true(level.collapse_tile_at(interior_cell))
	assert_false(level.maze.is_open(interior_cell.x, interior_cell.y))
	assert_true(level._astar.is_point_solid(interior_cell))


func test_collapse_tile_at_refuses_the_boundary() -> void:
	var level := _make_level()
	assert_false(level.collapse_tile_at(Vector2i(0, 0)), "boundary tiles can never be collapsed")


func test_collapse_tile_at_on_an_already_wall_tile_is_a_noop() -> void:
	var level := _make_level()
	var wall_cell := Vector2i(2, 2) # even/even — always a wall in the expanded grid
	assert_false(level.maze.is_open(wall_cell.x, wall_cell.y))
	assert_false(level.collapse_tile_at(wall_cell))
