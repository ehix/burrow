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


func test_spawn_larva_at_random_never_lands_on_a_centipede_tile() -> void:
	var level := _make_level()
	for node in level.get_tree().get_nodes_in_group("centipedes"):
		node.free()
	var player_tile := level.tile_of(level.player.global_position)
	var enemy_tile := level.tile_of(level.enemy.global_position)
	var eligible: Array[Vector2i] = []
	for cell in level.maze.open_cells():
		if not level.is_boundary(cell) and cell != player_tile and cell != enemy_tile:
			eligible.append(cell)
	# Reserve every eligible cell except one for a Centipede body -- the
	# single remaining cell is the only place a new larva could legally land.
	var free_cell: Vector2i = eligible[0]
	var body: Array[Vector2i] = eligible.slice(1)
	var centipede := Centipede.new()
	level.add_child(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(body)
	for node in level.get_tree().get_nodes_in_group("larvae"):
		node.free()

	level._spawn_larva_at_random()

	var larvae := level.get_tree().get_nodes_in_group("larvae")
	assert_eq(larvae.size(), 1, "still finds the one legal cell, not stuck refusing to spawn at all")
	assert_eq(level.tile_of((larvae[0] as Node2D).global_position), free_cell,
		"a new larva never lands on a tile a Centipede body already occupies")


func test_find_open_chain_never_includes_a_boundary_tile() -> void:
	var level := _make_level()
	var chain := level._find_open_chain(4, {})
	for tile in chain:
		assert_false(level.maze.is_boundary(tile.x, tile.y))
