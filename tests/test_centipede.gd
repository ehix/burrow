extends GutTest
## Centipede (sub-project H): shared hit-counter across the whole body,
## segment_at_tile() lookup, and spawn_at() laying out segment visuals to
## match its tile array. Movement (crawling/fleeing/relocating) is covered
## in later tasks' own test files as it's built.

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


func test_spawn_at_creates_one_segment_per_tile() -> void:
	var level := _make_level()
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]
	var centipede := _make_centipede(level, tiles)
	assert_eq(centipede._segments.size(), 3)


func test_spawn_at_positions_each_segment_at_its_tile_centre() -> void:
	var level := _make_level()
	var tiles: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2)]
	var centipede := _make_centipede(level, tiles)
	assert_eq(centipede._segments[0].global_position, level.tile_centre(Vector2i(1, 1)))
	assert_eq(centipede._segments[1].global_position, level.tile_centre(Vector2i(1, 2)))


func test_spawn_at_destroys_a_larva_already_sitting_on_a_claimed_tile() -> void:
	var level := _make_level()
	var tile := Vector2i(1, 2)
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	level.add_child(larva)
	larva.global_position = level.tile_centre(tile)

	_make_centipede(level, [Vector2i(1, 1), tile])

	assert_true(larva.is_queued_for_deletion(),
		"a body materializing on top of a larva squashes it, same as crawling into one")


func test_spawn_at_destroys_a_world_item_already_sitting_on_a_claimed_tile() -> void:
	var level := _make_level()
	var tile := Vector2i(1, 2)
	var item := Node2D.new()
	item.add_to_group("world_items")
	level.add_child(item)
	item.global_position = level.tile_centre(tile)

	_make_centipede(level, [Vector2i(1, 1), tile])

	assert_true(item.is_queued_for_deletion(),
		"a body materializing on top of an item destroys it, same as crawling into one")


func test_joins_the_centipedes_group() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1)])
	assert_true(centipede.is_in_group("centipedes"))


func test_take_hit_below_threshold_stays_blocking() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1)])
	centipede.hits_to_flee = 4
	centipede.take_hit()
	centipede.take_hit()
	centipede.take_hit()
	assert_eq(centipede.state, Centipede.State.BLOCKING)


func test_take_hit_at_threshold_begins_fleeing() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1)])
	centipede.hits_to_flee = 4
	for i in 4:
		centipede.take_hit()
	assert_eq(centipede.state, Centipede.State.FLEEING)


func test_take_hit_is_a_noop_once_already_fleeing() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1)])
	centipede.hits_to_flee = 2
	centipede.take_hit()
	centipede.take_hit() # now FLEEING
	centipede.take_hit() # must not error or re-trigger anything odd
	assert_eq(centipede.state, Centipede.State.FLEEING)


func test_segment_at_tile_finds_the_owning_centipede() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1), Vector2i(1, 2)])
	var found := Centipede.segment_at_tile(level.get_tree(), Vector2i(1, 2))
	assert_eq(found, centipede)


func test_segment_at_tile_returns_null_for_an_unoccupied_tile() -> void:
	var level := _make_level()
	_make_centipede(level, [Vector2i(1, 1)])
	var found := Centipede.segment_at_tile(level.get_tree(), Vector2i(5, 5))
	assert_null(found)


func test_hit_segment_at_registers_a_hit_on_the_shared_counter() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1), Vector2i(1, 2)])
	centipede.hits_to_flee = 4
	centipede.hit_segment_at(Vector2i(1, 2))
	centipede.hit_segment_at(Vector2i(1, 1))
	centipede.hit_segment_at(Vector2i(1, 2))
	assert_eq(centipede._hits, 3)


func test_hit_segment_at_nudges_only_the_exact_segment_struck() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1), Vector2i(1, 2)])
	var struck := centipede._segments[1]
	var untouched := centipede._segments[0]
	var struck_rest := struck.position
	var untouched_rest := untouched.position

	centipede.hit_segment_at(Vector2i(1, 2), Vector2.RIGHT)

	assert_ne(struck.position, struck_rest,
		"the exact segment struck visibly nudges on a hit -- reuses Blockade.take_hit()'s own CombatFx.shunt")
	assert_eq(untouched.position, untouched_rest, "an untouched segment doesn't nudge")


func test_get_segments_returns_the_live_segment_array() -> void:
	var level := _make_level()
	var centipede := _make_centipede(level, [Vector2i(1, 1), Vector2i(1, 2)])

	assert_eq(centipede.get_segments(), centipede._segments)


func test_level_is_blocked_true_on_a_centipede_tile_for_both_planes() -> void:
	var level := _make_level()
	_make_centipede(level, [Vector2i(3, 3)])
	assert_true(level.is_blocked(Vector2i(3, 3), Level.Layer.GROUND))
	assert_true(level.is_blocked(Vector2i(3, 3), Level.Layer.CEILING))
