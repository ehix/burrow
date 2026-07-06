extends GutTest
## Unit tests for the maze generator (design §9: connectivity + determinism).


func test_dimensions_are_expanded_representation() -> void:
	var maze := MazeGenerator.generate(5, 4, 123)
	assert_eq(maze.width, 5 * 2 + 1)
	assert_eq(maze.height, 4 * 2 + 1)


func test_every_open_cell_is_reachable() -> void:
	# Connectivity across several seeds and sizes.
	for seed_value in [0, 1, 42, 9999]:
		var maze := MazeGenerator.generate(8, 8, seed_value)
		assert_true(maze.is_fully_connected(),
			"maze with seed %d should have no isolated cells" % seed_value)


func test_same_seed_is_deterministic() -> void:
	var a := MazeGenerator.generate(10, 10, 7)
	var b := MazeGenerator.generate(10, 10, 7)
	assert_true(a.equals(b), "identical seed must produce an identical maze")


func test_different_seed_differs() -> void:
	var a := MazeGenerator.generate(10, 10, 7)
	var b := MazeGenerator.generate(10, 10, 8)
	assert_false(a.equals(b), "different seeds should (almost surely) differ")


func test_outer_border_is_solid_wall() -> void:
	var maze := MazeGenerator.generate(6, 6, 3)
	for x in maze.width:
		assert_false(maze.is_open(x, 0), "top border open at %d" % x)
		assert_false(maze.is_open(x, maze.height - 1), "bottom border open at %d" % x)
	for y in maze.height:
		assert_false(maze.is_open(0, y), "left border open at %d" % y)
		assert_false(maze.is_open(maze.width - 1, y), "right border open at %d" % y)


func test_cell_centres_are_open() -> void:
	# Every odd/odd tile is a carved cell centre.
	var maze := MazeGenerator.generate(6, 6, 11)
	assert_true(maze.is_open(1, 1))
	assert_true(maze.is_open(maze.width - 2, maze.height - 2))


func test_open_cell_count_matches_reachable() -> void:
	var maze := MazeGenerator.generate(7, 5, 55)
	var cells := maze.open_cells()
	assert_gt(cells.size(), 0)
	assert_eq(maze.reachable_count(cells[0]), cells.size())


func test_braiding_reduces_dead_ends() -> void:
	# Same seed: braided maze has strictly fewer dead-ends than the perfect one.
	var perfect := MazeGenerator.generate(8, 8, 123, 0.0)
	var braided := MazeGenerator.generate(8, 8, 123, 1.0)
	assert_gt(perfect.dead_end_count(), 0, "a perfect maze has dead-ends")
	assert_lt(braided.dead_end_count(), perfect.dead_end_count(),
		"braiding should remove dead-ends and add loops")


func test_braiding_stays_connected_and_deterministic() -> void:
	var a := MazeGenerator.generate(8, 8, 77, 0.7)
	var b := MazeGenerator.generate(8, 8, 77, 0.7)
	assert_true(a.is_fully_connected(), "braided maze stays fully connected")
	assert_true(a.equals(b), "braiding is deterministic for a fixed seed")


func test_full_braid_opens_more_passages() -> void:
	# Braiding only opens walls, so the braided maze has >= the open tiles of
	# the perfect one (and strictly more when any dead-end is braided).
	var perfect := MazeGenerator.generate(8, 8, 5, 0.0)
	var braided := MazeGenerator.generate(8, 8, 5, 1.0)
	assert_gt(braided.open_cells().size(), perfect.open_cells().size())
