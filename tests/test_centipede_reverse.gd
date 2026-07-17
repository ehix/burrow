extends GutTest
## Centipede's reverse-before-carve fallback (playtest follow-up to sub-
## project H's original boxed-in tunnel fallback, design §6): a body
## completely filling a 1-tile-wide dead-end corridor has its own tail
## sitting exactly where a forward path would need to go -- _find_path()
## correctly refuses to route through the body's own tiles, so no forward
## path can ever exist there, and the old behavior fell straight to
## _tunnel_toward()'s wall-carving fallback, which has no notion of which
## carved pockets actually connect anywhere and could destroy a large,
## visibly disruptive fraction of the map hunting for one that does
## (confirmed via a timed repro: 24 tiles carved, ~18 real seconds, for a
## case reversing resolves in one free, instant step). _reverse_body()
## tries leading with the tail's end instead -- always valid and free,
## since the tile behind the tail is exactly where the body walked in from
## -- before ever carving anything.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	for node in get_tree().get_nodes_in_group("centipedes"):
		node.free()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


## A fully deterministic maze so the dead-end shape (and the fact that
## _tunnel_toward() should never even be called) isn't at the mercy of
## MazeGenerator's random layout: a room at x=1..5,y=1..5, plus a 1-wide,
## 3-tile dead-end corridor at y=3,x=6..8 whose only connection to the room
## is its entrance at (6,3) -- adjacent to the room's own (5,3).
func _make_dead_end_level() -> Level:
	var level := _make_level()
	var width := 10
	var height := 8
	var cells := PackedByteArray()
	cells.resize(width * height)
	cells.fill(0)
	for y in range(1, 6):
		for x in range(1, 6):
			cells[y * width + x] = 1
	for x in range(6, 9):
		cells[3 * width + x] = 1
	level.maze = MazeData.new(cells, width, height)
	return level


## A minimal stand-in for Player/Enemy (mirrors test_centipede_crawl.gd's
## own _make_fake_spider()): just enough to exercise shove_spiders_out_of()
## without dragging in the whole Player/Enemy scene tree.
func _make_fake_spider(level: Level, tile: Vector2i) -> Node2D:
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	add_child_autofree(spider)
	spider.global_position = level.tile_centre(tile)
	var mover := GridMover.new()
	mover.name = "GridMover"
	mover.tile_size = Level.TILE_SIZE
	spider.add_child(mover)
	return spider


func test_reverse_body_flips_tiles_and_segments_together() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var second: Vector2i = Vector2i.ZERO
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var candidate: Vector2i = start + dir
		if level.maze.is_open(candidate.x, candidate.y):
			second = candidate
			break
	var centipede := _make_centipede(level, [start, second])
	var original_tiles := centipede._tiles.duplicate()
	var original_segments := centipede._segments.duplicate()

	centipede._reverse_body()

	assert_eq(centipede._tiles, [original_tiles[1], original_tiles[0]], "tiles reversed")
	assert_eq(centipede._segments, [original_segments[1], original_segments[0]], "segments reversed to match")
	assert_eq(centipede._tiles[0], second, "the old tail is now the head")


## The core regression: a 3-segment body completely fills the dead-end
## corridor (head at the deepest tile, tail at the entrance) -- the room
## beyond the tail is the ONLY place a boundary-adjacent flee target can
## be, so a forward path can never exist (the tail itself blocks it), but
## reversing finds one immediately, at zero carving cost.
func test_start_crawl_reverses_instead_of_carving_when_the_tail_blocks_the_only_route() -> void:
	var level := _make_dead_end_level()
	var centipede := _make_centipede(level, [Vector2i(8, 3), Vector2i(7, 3), Vector2i(6, 3)])
	centipede._target = Vector2i(1, 1) # deep in the room -- only reachable by reversing out
	var open_before := level.maze.open_cells().size()

	centipede._start_crawl()

	assert_false(centipede._path.is_empty(), "a path was found")
	assert_eq(centipede._tiles[0], Vector2i(6, 3), "reversed to lead with the old tail")
	assert_eq(level.maze.open_cells().size(), open_before, "zero walls carved -- reversing is free")


## Complement, phrased the way a playtester would judge it: a full flee
## through a dead-end a realistic multi-segment body completely fills
## still ends up carving nothing at all (matches test_centipede_flee.gd's
## own test_a_full_flee_never_carves_more_than_a_handful_of_walls, just for
## the specific shape that used to defeat it).
func test_a_full_flee_out_of_a_self_filled_dead_end_carves_nothing() -> void:
	var level := _make_dead_end_level()
	var centipede := _make_centipede(level, [Vector2i(8, 3), Vector2i(7, 3), Vector2i(6, 3)])
	centipede.body_length = 3
	centipede.hits_to_flee = 1
	var open_before := level.maze.open_cells().size()

	centipede.take_hit()
	var ticks := 0
	var exiting := false
	while is_instance_valid(centipede) and not centipede.is_queued_for_deletion() and ticks < 200:
		if exiting:
			centipede._exit_step()
		else:
			centipede._crawl_step()
			exiting = centipede._exit_steps_remaining > 0
		ticks += 1

	assert_true(centipede.is_queued_for_deletion(), "sanity: the flee actually completed")
	assert_eq(level.maze.open_cells().size(), open_before, "reversing out of its own dead end never needs to carve")


## Playtest ask: everything else must keep working after a reversal, named
## explicitly -- a spider standing in the crawl's way still gets shoved,
## exactly like test_centipede_crawl.gd's own equivalent forward-direction
## test.
func test_crawl_step_after_a_reversal_still_shoves_a_spider_out_of_the_way() -> void:
	var level := _make_dead_end_level()
	var centipede := _make_centipede(level, [Vector2i(8, 3), Vector2i(7, 3), Vector2i(6, 3)])
	centipede._target = Vector2i(1, 1)
	centipede._start_crawl() # reverses -- _tiles[0] is now (6,3)
	var next_tile: Vector2i = centipede._path[1]
	var push_dir := next_tile - centipede._tiles[0]
	var spider := _make_fake_spider(level, next_tile)
	var mover: GridMover = spider.get_node("GridMover")

	centipede._crawl_step()

	assert_eq(mover.committed_tile(), next_tile + push_dir,
		"a spider standing in the reversed body's way still gets shoved along its travel direction")
	assert_eq(centipede._tiles[0], next_tile, "the body still advances once the spider's cleared")


## Playtest ask, continued: combat hit-detection by tile still finds the
## right segment after a reversal -- _tiles and _segments stay paired by
## index, they're just walked from the other end now.
func test_hit_segment_at_still_finds_the_correct_segment_after_a_reversal() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var second: Vector2i = Vector2i.ZERO
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var candidate: Vector2i = start + dir
		if level.maze.is_open(candidate.x, candidate.y):
			second = candidate
			break
	var centipede := _make_centipede(level, [start, second])
	var segment_at_second := centipede._segments[1]

	centipede._reverse_body()
	centipede.hit_segment_at(second)

	assert_eq(centipede._hits, 1, "the hit still registers")
	# second is now _tiles[0] (index 0) post-reversal -- confirm the SAME
	# segment node (not a mismatched one) is still the one at that tile.
	assert_eq(centipede._segments[0], segment_at_second, "the tile-to-segment mapping survived the reversal")
