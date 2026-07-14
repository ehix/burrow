extends GutTest
## Centipede's boxed-in tunnel fallback (sub-project H, design §6): when no
## open+dry path exists to the target, it carves the single best adjacent
## wall tile and retries -- the "escape-through-tunnels... unless blocked
## in" case from the roadmap's original phrasing.

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


func _seal_in(level: Level, tile: Vector2i) -> void:
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		level.set_water_at(tile + dir, true) # no-ops harmlessly on an already-wall neighbor


func test_tunnel_toward_carves_exactly_one_wall_tile_when_boxed_in() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	_seal_in(level, start)
	var centipede := _make_centipede(level, [start])
	var open_before := level.maze.open_cells().size()

	var carved: bool = centipede._tunnel_toward(cells[cells.size() - 1])

	assert_true(carved)
	assert_eq(level.maze.open_cells().size(), open_before + 1, "exactly one new tile was carved open")


func test_tunnel_toward_never_carves_a_boundary_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	_seal_in(level, start)
	var centipede := _make_centipede(level, [start])
	var before: Dictionary = {}
	for cell in level.maze.open_cells():
		before[cell] = true

	centipede._tunnel_toward(cells[cells.size() - 1])

	for cell in level.maze.open_cells():
		if not before.has(cell):
			assert_false(level.is_boundary(cell), "the newly carved tile is never on the boundary")


func test_start_crawl_finds_a_path_after_tunneling_through_when_boxed_in() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	_seal_in(level, start)
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]

	centipede._start_crawl()

	assert_false(centipede._path.is_empty(), "boxed-in start_crawl tunnels through and finds a path")
