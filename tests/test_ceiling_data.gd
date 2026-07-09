extends GutTest
## CeilingData (design §1): shares ground wall geometry, but ignores pits —
## the ceiling plane bypasses a ground hazard that blocks ground movement.


func test_ceiling_open_matches_ground_open() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	var ceiling := CeilingData.new(maze)
	for cell in maze.open_cells():
		assert_true(ceiling.is_open(cell.x, cell.y))
	assert_false(ceiling.is_open(0, 0), "the ground's border wall blocks the ceiling too")


func test_ceiling_ignores_a_ground_pit() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	var ceiling := CeilingData.new(maze)
	maze.set_pit(1, 1, true)
	assert_true(maze.is_ground_blocked(1, 1), "the pit blocks ground movement")
	assert_false(ceiling.is_blocked(1, 1), "the ceiling passes straight over it")


func test_ceiling_blocked_matches_wall_geometry() -> void:
	var maze := MazeGenerator.generate(5, 4, 1)
	var ceiling := CeilingData.new(maze)
	assert_true(ceiling.is_blocked(0, 0), "a wall blocks the ceiling")
	assert_false(ceiling.is_blocked(1, 1), "an open cell centre doesn't")
