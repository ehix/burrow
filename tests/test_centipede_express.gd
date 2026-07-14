extends GutTest
## CentipedeExpress (sub-project H follow-up, found during playtest): after
## carving its straight corridor, a real Centipede now rides it via
## Level.spawn_centipede_along() -- the hazard's name stops being purely
## metaphorical (it used to only carve tunnel, never spawn a creature).

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	# This file drives its own carved lines directly -- free any centipede
	# Level.build() auto-seeded (Task 8) so it can never collide with (or be
	# found instead of) the rider these tests expect to see spawned.
	for node in level.get_tree().get_nodes_in_group("centipedes"):
		node.free()
	return level


func _carve_line(level: Level, y: int) -> Array[Vector2i]:
	var line: Array[Vector2i] = []
	for x in range(1, level.maze.width - 1):
		level.dev_remove_wall_at(Vector2i(x, y))
		line.append(Vector2i(x, y))
	return line


func test_spawn_centipede_along_places_a_body_length_chain_on_the_line() -> void:
	var level := _make_level()
	var line := _carve_line(level, 3)

	level.spawn_centipede_along(line)

	var centipedes := level.get_tree().get_nodes_in_group("centipedes")
	assert_eq(centipedes.size(), 1)
	var centipede := centipedes[0] as Centipede
	assert_eq(centipede._tiles.size(), centipede.body_length)
	for tile in centipede._tiles:
		assert_true(tile in line, "the rider's whole body sits on the carved line")


func test_spawn_centipede_along_does_nothing_when_the_line_is_shorter_than_a_body() -> void:
	var level := _make_level()
	level.dev_remove_wall_at(Vector2i(1, 1))
	var short_line: Array[Vector2i] = [Vector2i(1, 1)]

	level.spawn_centipede_along(short_line)

	assert_eq(level.get_tree().get_nodes_in_group("centipedes").size(), 0,
		"a line too short for even one body-length run spawns nothing, not a truncated body")


func test_spawn_centipede_along_avoids_a_spider_standing_on_the_line() -> void:
	var level := _make_level()
	var line := _carve_line(level, 3)
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	level.add_child(spider)
	spider.global_position = level.tile_centre(Vector2i(2, 3))

	level.spawn_centipede_along(line)

	var centipede := level.get_tree().get_nodes_in_group("centipedes")[0] as Centipede
	assert_false(Vector2i(2, 3) in centipede._tiles, "never overlaps a spider standing on the line")


func test_spawn_centipede_along_avoids_another_centipedes_body() -> void:
	var level := _make_level()
	var line := _carve_line(level, 3)
	var blocker := Centipede.new()
	level.add_child(blocker)
	blocker.bind_level(level)
	blocker.spawn_at([Vector2i(2, 3)])

	level.spawn_centipede_along(line)

	var rider: Centipede = null
	for node in level.get_tree().get_nodes_in_group("centipedes"):
		if node != blocker:
			rider = node
	assert_not_null(rider, "still finds a clear run elsewhere on the line")
	assert_false(Vector2i(2, 3) in rider._tiles, "never overlaps another Centipede's own body")


func test_trigger_carves_a_straight_line_and_sends_a_rider_down_it() -> void:
	var level := _make_level()
	var express := CentipedeExpress.new()

	express.trigger(level)

	assert_eq(level.get_tree().get_nodes_in_group("centipedes").size(), 1,
		"the express hazard spawns an actual Centipede on the corridor it just carved")
