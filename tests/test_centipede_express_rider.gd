extends GutTest
## CentipedeExpressRider (Centipede Express hazard's own creature, corrected
## after playtest feedback -- it's a transient, always-moving creature that
## crawls straight across the map carving/destroying/shoving as it goes,
## deflecting 90 degrees around another Centipede's body, never a stationary
## obstacle like the seeded Centipede).

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	for node in level.get_tree().get_nodes_in_group("centipedes"):
		node.free()
	return level


func _make_rider(level: Level, entry: Vector2i, direction: Vector2i) -> CentipedeExpressRider:
	var rider := CentipedeExpressRider.new()
	add_child_autofree(rider)
	rider.bind_level(level)
	rider.start_run(entry, direction)
	return rider


## Mirrors test_centipede_crawl.gd's own fake -- just enough to exercise
## Centipede.shove_spiders_out_of() without dragging in Player/Enemy.
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


func test_start_run_tucks_the_whole_body_off_map_behind_entry() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT)

	for i in rider.body_length:
		assert_eq(rider._tiles[i], entry - Vector2i.RIGHT * (i + 1))


func test_first_step_brings_the_head_onto_the_entry_tile() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT)

	rider._step()

	assert_eq(rider._tiles[0], entry)
	assert_eq(rider._segments[0].global_position, level.tile_centre(entry))


func test_step_carves_a_wall_tile_directly_ahead() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT)
	rider._step() # head arrives at entry
	var next_tile := entry + Vector2i.RIGHT
	level.maze.set_wall(next_tile.x, next_tile.y) # force it to be a wall

	rider._step()

	assert_true(level.maze.is_open(next_tile.x, next_tile.y), "carves the next tile open if it's currently a wall")
	assert_eq(rider._tiles[0], next_tile)


func test_step_never_carves_the_boundary_ring() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.LEFT)
	rider._step() # head arrives at entry
	rider._step() # next tile is x=0, the boundary ring

	assert_false(level.maze.is_open(0, 3), "the boundary ring itself is never carved open")


func test_step_destroys_a_larva_on_the_tile_it_enters() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT)
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	level.add_child(larva)
	larva.global_position = level.tile_centre(entry)

	rider._step()

	assert_true(larva.is_queued_for_deletion(), "a larva on the tile the head steps onto is destroyed")


func test_step_destroys_a_world_item_on_the_tile_it_enters() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT)
	var item := Node2D.new()
	item.add_to_group("world_items")
	level.add_child(item)
	item.global_position = level.tile_centre(entry)

	rider._step()

	assert_true(item.is_queued_for_deletion(), "an item on the tile the head steps onto is destroyed")


func test_step_shoves_a_spider_off_the_tile_it_enters() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT)
	var spider := _make_fake_spider(level, entry)
	var mover: GridMover = spider.get_node("GridMover")

	rider._step()

	assert_eq(mover.committed_tile(), entry + Vector2i.RIGHT,
		"a spider caught in the rider's path gets shoved further along its travel direction")
	assert_eq(rider._tiles[0], entry, "the rider still advances once the tile is cleared")


func test_step_deflects_90_degrees_around_another_centipedes_body() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT)
	rider._step() # head arrives at entry
	var blocked_tile := entry + Vector2i.RIGHT
	var blocker := Centipede.new()
	level.add_child(blocker)
	blocker.bind_level(level)
	blocker.spawn_at([blocked_tile])

	rider._step()

	assert_eq(rider._direction, Vector2i.DOWN, "turns 90 degrees clockwise instead of plowing through")
	assert_ne(rider._tiles[0], blocked_tile, "never steps onto another Centipede's own body")
	assert_eq(rider._tiles[0], entry + Vector2i.DOWN, "advances in its new heading the same tick")


func test_step_deflects_again_if_the_new_heading_is_also_blocked() -> void:
	var level := _make_level()
	var entry := Vector2i(3, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT)
	rider._step() # head arrives at entry
	var blocker := Centipede.new()
	level.add_child(blocker)
	blocker.bind_level(level)
	# Blocks straight ahead (RIGHT) and the first clockwise deflection (DOWN).
	blocker.spawn_at([entry + Vector2i.RIGHT, entry + Vector2i.DOWN])

	rider._step()

	assert_eq(rider._direction, Vector2i.LEFT, "keeps turning clockwise until it finds a clear heading")
	assert_eq(rider._tiles[0], entry + Vector2i.LEFT)


func test_run_frees_itself_once_the_tail_clears_the_boundary_ring_not_just_reaches_it() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.LEFT) # heads straight for the near edge (x=0)

	var ticks := 0
	while is_instance_valid(rider) and not rider.is_queued_for_deletion() and ticks < 50:
		rider._step()
		ticks += 1

	assert_true(rider.is_queued_for_deletion(), "frees itself once the whole body has exited")
	# queue_free() defers actual destruction -- _tiles is still readable here.
	# The boundary ring tile is x=0; fully "exited" means the tail's x has
	# gone strictly past it, not merely reached it -- the ring tile itself
	# is still a solid, rendered wall block, not genuinely off-map (found
	# via playtest: it looked like it vanished a beat too early).
	var tail: Vector2i = rider._tiles[rider._tiles.size() - 1]
	assert_lt(tail.x, 0, "the tail clears the boundary ring tile itself, not just reaches it")
