extends GutTest
## Centipede's crawl stepper (sub-project H, design §5): the shared engine
## both FLEEING (retreat to the map boundary, despawn) and RELOCATING
## (flood-forced move to a fresh spot, resume BLOCKING) drive. Tested by
## calling _crawl_step() directly, never by awaiting the real
## crawl_step_time SceneTreeTimer -- mirrors how sub-project G's
## WaterIngress tested _flood_ring/_drain_ring directly rather than through
## their real timer scheduling.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	# This file places its own centipede(s) at tiles it controls directly --
	# free any centipede Level.build() auto-seeded (Task 8) so it can never
	# collide with (or be found instead of) the tiles these tests place.
	for node in get_tree().get_nodes_in_group("centipedes"):
		node.free()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


## A minimal stand-in for Player/Enemy: just enough to exercise
## _shove_spiders_out_of() (group membership + a real GridMover child at
## `tile`) without dragging in the whole Player/Enemy scene tree. Its
## GridMover has no block_check and no PhysicsBody2D parent, so
## GridMover._is_blocked() falls back to `body == null -> false` -- i.e.
## never blocked by default, letting a test opt into blocking a specific
## direction via `mover.block_check` when it needs to.
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


func test_crawl_step_advances_the_head_and_shifts_the_tail() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	var expected_next: Vector2i = centipede._path[1]

	centipede._crawl_step()

	assert_eq(centipede._tiles[0], expected_next, "the head moved to the next path tile")


func test_crawl_step_repositions_segments_to_match_the_new_tiles() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()

	centipede._crawl_step()

	assert_eq(centipede._segments[0].global_position, level.tile_centre(centipede._tiles[0]))


func test_crawl_step_destroys_a_larva_on_the_newly_entered_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	var next_tile: Vector2i = centipede._path[1]
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	level.add_child(larva)
	larva.global_position = level.tile_centre(next_tile)

	centipede._crawl_step()

	assert_true(larva.is_queued_for_deletion(), "a larva on the tile the head just entered is destroyed")


func test_crawl_step_destroys_a_world_item_on_the_newly_entered_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	var next_tile: Vector2i = centipede._path[1]
	var item := Node2D.new()
	item.add_to_group("world_items")
	level.add_child(item)
	item.global_position = level.tile_centre(next_tile)

	centipede._crawl_step()

	assert_true(item.is_queued_for_deletion(), "an item on the tile the head just entered is destroyed too")


func test_crawl_step_shoves_a_spider_off_the_tile_it_steps_into() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	var next_tile: Vector2i = centipede._path[1]
	var push_dir := next_tile - start
	var spider := _make_fake_spider(level, next_tile)
	var mover: GridMover = spider.get_node("GridMover")

	centipede._crawl_step()

	assert_eq(mover.committed_tile(), next_tile + push_dir,
		"a spider standing in the body's way gets shoved further along its own travel direction")
	assert_eq(centipede._tiles[0], next_tile,
		"the body still advances into the tile once it's cleared -- it's a strong boundary, not a stalled one")


func test_crawl_step_shove_falls_back_to_another_direction_when_the_push_direction_is_blocked() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	var next_tile: Vector2i = centipede._path[1]
	var push_dir := next_tile - start
	var spider := _make_fake_spider(level, next_tile)
	var mover: GridMover = spider.get_node("GridMover")
	mover.block_check = func(dir: Vector2i) -> bool: return dir == push_dir

	centipede._crawl_step()

	assert_ne(mover.committed_tile(), next_tile,
		"blocked straight ahead -- the spider still gets shoved somewhere, not left overlapping the body")
	assert_ne(mover.committed_tile(), next_tile + push_dir,
		"the straight-ahead direction is the one that's blocked, so the fallback must pick another")


func test_arriving_at_the_target_while_fleeing_frees_the_centipede() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede.state = Centipede.State.FLEEING
	centipede._target = start # already there -- one call should arrive immediately
	centipede._path = [start]

	centipede._crawl_step()
	# Arriving no longer frees on the spot -- it begins a body_length-step
	# exit crawl through the boundary (see _begin_exit()'s own doc comment).
	# Pump that stepper directly too, same convention as every other test in
	# this file driving _crawl_step() itself rather than the real timer.
	var exit_ticks := 0
	while not centipede.is_queued_for_deletion() and exit_ticks < 10:
		centipede._exit_step()
		exit_ticks += 1

	assert_true(centipede.is_queued_for_deletion(), "fleeing that reaches its target despawns")


func test_arriving_at_the_target_while_fleeing_does_not_free_it_instantly() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede.state = Centipede.State.FLEEING
	centipede._target = start
	centipede._path = [start]

	centipede._crawl_step()

	assert_false(centipede.is_queued_for_deletion(),
		"the body keeps crawling out through the boundary instead of vanishing whole the instant it arrives")
	assert_eq(centipede._exit_steps_remaining, centipede.body_length + 1,
		"the exit crawl takes body_length + 1 more steps -- enough for the tail to clear the boundary ring itself, not just reach it")


func test_exit_step_advances_the_head_and_moves_its_segment_same_as_an_ordinary_crawl_step() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [level.maze.open_cells()[0]])
	var boundary_tile: Vector2i = centipede._nearest_boundary_tile()
	centipede._tiles = [boundary_tile]
	centipede._sync_segments()
	centipede.state = Centipede.State.FLEEING
	centipede._target = boundary_tile
	centipede._path = [boundary_tile]
	centipede._crawl_step() # arrives -- begins the exit crawl
	var head_before := centipede._tiles[0]

	centipede._exit_step()

	assert_ne(centipede._tiles[0], head_before,
		"the head keeps advancing one tile per exit step, same as an ordinary crawl step")
	assert_eq(centipede._segments[0].global_position, level.tile_centre(centipede._tiles[0]),
		"the segment visual keeps following the tile during the exit crawl too, not popping out of existence")


func test_arriving_at_the_target_while_relocating_returns_to_blocking() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede.state = Centipede.State.RELOCATING
	centipede._target = start
	centipede._path = [start]

	centipede._crawl_step()

	assert_eq(centipede.state, Centipede.State.BLOCKING, "relocating that arrives resumes blocking in place")


func test_crawl_step_is_a_noop_on_a_freed_level() -> void:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	for node in level.get_tree().get_nodes_in_group("centipedes"):
		node.free()
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])
	centipede.state = Centipede.State.FLEEING
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	level.queue_free()
	await get_tree().process_frame

	centipede._crawl_step() # must not error on a freed level

	assert_true(true, "reached this point without erroring")
