extends GutTest
## Centipede's local BFS (sub-project H, design §6): avoids walls, water,
## and the body's own trailing tiles; returns [] when unreachable. Tested
## directly (no timers involved yet -- the crawl stepper that calls this on
## a schedule is a later task). Uses dynamically-derived open cells rather
## than hardcoded coordinates for multi-tile scenarios, since the maze
## layout between odd/odd cell-centres isn't guaranteed by MazeData's own
## contract -- only that all open cells are mutually reachable.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


func test_find_path_returns_just_the_start_when_already_there() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	var path: Array[Vector2i] = centipede._find_path(start, start)
	assert_eq(path, [start])


func test_find_path_finds_a_route_between_two_open_cells() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var goal: Vector2i = cells[cells.size() - 1]
	var centipede := _make_centipede(level, [start])

	var path: Array[Vector2i] = centipede._find_path(start, goal)

	assert_eq(path[0], start)
	assert_eq(path[path.size() - 1], goal, "every open cell is mutually reachable")


func test_find_path_avoids_a_flooded_intermediate_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var goal: Vector2i = cells[cells.size() - 1]
	var centipede := _make_centipede(level, [start])
	var dry_path: Array[Vector2i] = centipede._find_path(start, goal)
	assert_gt(dry_path.size(), 2, "sanity: needs at least one intermediate tile to flood")
	var blocked_tile: Vector2i = dry_path[1]
	level.set_water_at(blocked_tile, true)

	var wet_path: Array[Vector2i] = centipede._find_path(start, goal)

	assert_false(blocked_tile in wet_path, "the newly-flooded tile is never stepped on")


func test_find_path_returns_empty_when_completely_sealed_in() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		level.set_water_at(start + dir, true) # no-ops harmlessly on any neighbor that's already a wall
	var centipede := _make_centipede(level, [start])

	var path: Array[Vector2i] = centipede._find_path(start, cells[cells.size() - 1])

	assert_eq(path, [], "every neighbor is either a wall or now flooded -- nowhere to go")


func test_find_path_never_steps_on_the_bodys_own_trailing_tiles() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var second_segment := Vector2i.ZERO
	var found_neighbor := false
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var candidate: Vector2i = start + dir
		if level.maze.is_open(candidate.x, candidate.y):
			second_segment = candidate
			found_neighbor = true
			break
	assert_true(found_neighbor, "sanity: the maze must have at least one open neighbor here")
	var centipede := _make_centipede(level, [start, second_segment])
	var goal: Vector2i = cells[cells.size() - 1]
	if goal == second_segment:
		goal = cells[cells.size() - 2]

	var path: Array[Vector2i] = centipede._find_path(start, goal)

	assert_false(second_segment in path, "the body's own second segment is never stepped on")
