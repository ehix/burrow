extends GutTest
## Level's Centipede seeding (sub-project H): a connected chain of
## body_length open tiles, reserved away from both spawns. Mirrors
## test_level_world_seeding.gd's earthworm-seeding test in spirit -- that
## file's own earthworm test is removed in this plan's final task alongside
## Earthworm's full deletion.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_seeds_the_expected_number_of_centipedes() -> void:
	var level := _make_level()
	var centipedes := level.get_tree().get_nodes_in_group("centipedes")
	assert_eq(centipedes.size(), Level.CENTIPEDE_COUNT)


func test_seeded_centipede_body_is_a_connected_chain() -> void:
	var level := _make_level()
	var centipedes := level.get_tree().get_nodes_in_group("centipedes")
	var centipede := centipedes[0] as Centipede
	assert_eq(centipede._tiles.size(), centipede.body_length)
	for i in range(1, centipede._tiles.size()):
		var a: Vector2i = centipede._tiles[i - 1]
		var b: Vector2i = centipede._tiles[i]
		var dist := absi(a.x - b.x) + absi(a.y - b.y)
		assert_eq(dist, 1, "consecutive body tiles are always orthogonally adjacent")


func test_seeded_centipede_is_away_from_both_spawns() -> void:
	var level := _make_level()
	var player_tile := level.tile_of(level.player.global_position)
	var enemy_tile := level.tile_of(level.enemy.global_position)
	var centipedes := level.get_tree().get_nodes_in_group("centipedes")
	var centipede := centipedes[0] as Centipede
	for tile in centipede._tiles:
		assert_ne(tile, player_tile)
		assert_ne(tile, enemy_tile)


func test_find_open_chain_never_includes_a_boundary_tile() -> void:
	var level := _make_level()
	var chain := level._find_open_chain(4, {})
	for tile in chain:
		assert_false(level.maze.is_boundary(tile.x, tile.y))
