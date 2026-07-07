extends GutTest
## GridNav builds an AStarGrid2D from a maze and paths over open tiles only.


func test_path_stays_on_open_tiles() -> void:
	var maze := MazeGenerator.generate(6, 6, 42)
	var astar := GridNav.build(maze, 48)
	var open := maze.open_cells()
	var from: Vector2i = open[0]
	var to: Vector2i = open[open.size() - 1]
	var route := GridNav.path(astar, from, to)
	assert_gt(route.size(), 0, "a route exists between two open cells")
	for tile in route:
		assert_true(maze.is_open(tile.x, tile.y),
			"route tile %s must be open floor" % tile)


func test_path_is_deterministic() -> void:
	var maze := MazeGenerator.generate(6, 6, 7)
	var a := GridNav.build(maze, 48)
	var b := GridNav.build(maze, 48)
	var open := maze.open_cells()
	var r1 := GridNav.path(a, open[0], open[open.size() - 1])
	var r2 := GridNav.path(b, open[0], open[open.size() - 1])
	assert_eq(r1, r2, "same maze yields the same path")


func test_path_to_a_wall_is_empty() -> void:
	var maze := MazeGenerator.generate(6, 6, 7)
	var astar := GridNav.build(maze, 48)
	# (0,0) is always the solid outer border.
	var route := GridNav.path(astar, Vector2i(1, 1), Vector2i(0, 0))
	assert_eq(route.size(), 0, "no path into a solid tile")
