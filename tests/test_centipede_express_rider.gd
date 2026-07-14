extends GutTest
## CentipedeExpressRider (Centipede Express hazard's own creature, corrected
## after playtest feedback on the first pass -- it's a transient, always-
## moving creature that crawls straight across the map carving/destroying/
## shoving as it goes, never a stationary obstacle like the seeded Centipede).

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	for node in level.get_tree().get_nodes_in_group("centipedes"):
		node.free()
	return level


func _make_rider(level: Level, entry: Vector2i, direction: Vector2i, steps: int) -> CentipedeExpressRider:
	var rider := CentipedeExpressRider.new()
	add_child_autofree(rider)
	rider.bind_level(level)
	rider.start_run(entry, direction, steps)
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
	var rider := _make_rider(level, entry, Vector2i.RIGHT, 5)

	for i in rider.body_length:
		assert_eq(rider._tiles[i], entry - Vector2i.RIGHT * (i + 1))


func test_first_step_brings_the_head_onto_the_entry_tile() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT, 5)

	rider._step()

	assert_eq(rider._tiles[0], entry)
	assert_eq(rider._segments[0].global_position, level.tile_centre(entry))


func test_step_carves_a_wall_tile_directly_ahead() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT, 5)
	rider._step() # head arrives at entry
	var next_tile := entry + Vector2i.RIGHT
	level.maze.set_wall(next_tile.x, next_tile.y) # force it to be a wall

	rider._step()

	assert_true(level.maze.is_open(next_tile.x, next_tile.y), "carves the next tile open if it's currently a wall")
	assert_eq(rider._tiles[0], next_tile)


func test_step_never_carves_the_boundary_ring() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.LEFT, 0)
	rider._step() # head arrives at entry
	rider._step() # next tile is x=0, the boundary ring

	assert_false(level.maze.is_open(0, 3), "the boundary ring itself is never carved open")


func test_step_destroys_a_larva_on_the_tile_it_enters() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT, 5)
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	level.add_child(larva)
	larva.global_position = level.tile_centre(entry)

	rider._step()

	assert_true(larva.is_queued_for_deletion(), "a larva on the tile the head steps onto is destroyed")


func test_step_destroys_a_world_item_on_the_tile_it_enters() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT, 5)
	var item := Node2D.new()
	item.add_to_group("world_items")
	level.add_child(item)
	item.global_position = level.tile_centre(entry)

	rider._step()

	assert_true(item.is_queued_for_deletion(), "an item on the tile the head steps onto is destroyed")


func test_step_shoves_a_spider_off_the_tile_it_enters() -> void:
	var level := _make_level()
	var entry := Vector2i(1, 3)
	var rider := _make_rider(level, entry, Vector2i.RIGHT, 5)
	var spider := _make_fake_spider(level, entry)
	var mover: GridMover = spider.get_node("GridMover")

	rider._step()

	assert_eq(mover.committed_tile(), entry + Vector2i.RIGHT,
		"a spider caught in the rider's path gets shoved further along its travel direction")
	assert_eq(rider._tiles[0], entry, "the rider still advances once the tile is cleared")


func test_run_frees_itself_after_the_tail_clears_the_far_edge() -> void:
	var level := _make_level()
	var rider := _make_rider(level, Vector2i(1, 3), Vector2i.RIGHT, 2)

	var ticks := 0
	while is_instance_valid(rider) and not rider.is_queued_for_deletion() and ticks < 50:
		rider._step()
		ticks += 1

	assert_true(rider.is_queued_for_deletion(), "frees itself once the whole body has exited the far side")
	assert_eq(ticks, 2 + rider.body_length, "exactly total_steps + body_length steps -- no more, no less")
