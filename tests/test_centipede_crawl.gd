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
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


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


func test_arriving_at_the_target_while_fleeing_frees_the_centipede() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	centipede.state = Centipede.State.FLEEING
	centipede._target = start # already there -- one call should arrive immediately
	centipede._path = [start]

	centipede._crawl_step()

	assert_true(centipede.is_queued_for_deletion(), "fleeing that reaches its target despawns")


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
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])
	centipede.state = Centipede.State.FLEEING
	centipede._target = cells[cells.size() - 1]
	centipede._start_crawl()
	level.queue_free()
	await get_tree().process_frame

	centipede._crawl_step() # must not error on a freed level

	assert_true(true, "reached this point without erroring")
