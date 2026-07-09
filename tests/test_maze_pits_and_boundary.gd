extends GutTest
## MazeData's new ground-hazard overlay and boundary/wall mutators (design §1
## and §7): is_boundary, set_wall, and the pit flag driving is_ground_blocked.


func test_is_boundary_true_on_every_edge() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	for x in maze.width:
		assert_true(maze.is_boundary(x, 0), "top edge is boundary")
		assert_true(maze.is_boundary(x, maze.height - 1), "bottom edge is boundary")
	for y in maze.height:
		assert_true(maze.is_boundary(0, y), "left edge is boundary")
		assert_true(maze.is_boundary(maze.width - 1, y), "right edge is boundary")


func test_is_boundary_false_on_an_interior_cell() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	assert_false(maze.is_boundary(1, 1))


func test_set_wall_is_inverse_of_set_open() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	assert_true(maze.is_open(1, 1), "a cell centre is open")
	maze.set_wall(1, 1)
	assert_false(maze.is_open(1, 1))


func test_set_wall_out_of_bounds_is_a_noop() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	maze.set_wall(-1, -1) # must not error
	maze.set_wall(999, 999)
	assert_true(maze.is_open(1, 1), "an out-of-bounds call must not touch in-bounds cells")
	maze.set_wall(999, 999)


func test_pit_blocks_ground_but_tile_stays_open() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	maze.set_pit(1, 1, true)
	assert_true(maze.is_open(1, 1), "a pit is not a wall")
	assert_true(maze.is_pit(1, 1))
	assert_true(maze.is_ground_blocked(1, 1), "a pit blocks ground movement")


func test_a_wall_is_ground_blocked_without_being_a_pit() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	assert_false(maze.is_open(0, 0), "the border is a wall")
	assert_false(maze.is_pit(0, 0))
	assert_true(maze.is_ground_blocked(0, 0), "a wall blocks ground movement too")


func test_set_pit_on_a_wall_tile_is_a_noop() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	maze.set_pit(0, 0, true) # (0,0) is a wall — nothing to flag
	assert_false(maze.is_pit(0, 0))


func test_clearing_a_pit_restores_normal_ground_traversal() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	maze.set_pit(1, 1, true)
	maze.set_pit(1, 1, false)
	assert_false(maze.is_pit(1, 1))
	assert_false(maze.is_ground_blocked(1, 1))
