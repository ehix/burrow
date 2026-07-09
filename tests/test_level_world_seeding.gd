extends GutTest
## Level's world-item and earthworm seeding (design §5, §6): placed on
## random open, non-spawn tiles each build.


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_seeds_earthworms_away_from_both_spawns() -> void:
	var level := _make_level()
	var player_tile := level.tile_of(level.player.global_position)
	var enemy_tile := level.tile_of(level.enemy.global_position)
	var worms := level.get_tree().get_nodes_in_group("earthworms")
	assert_eq(worms.size(), Level.EARTHWORM_COUNT)
	for worm in worms:
		var tile: Vector2i = level.tile_of((worm as Node2D).global_position)
		assert_ne(tile, player_tile)
		assert_ne(tile, enemy_tile)


func test_seeds_the_expected_number_of_world_items() -> void:
	var level := _make_level()
	var items := level.get_tree().get_nodes_in_group("world_items")
	assert_eq(items.size(), Level.ITEM_SPAWN_COUNT)


func test_world_items_are_away_from_both_spawns() -> void:
	var level := _make_level()
	var player_tile := level.tile_of(level.player.global_position)
	var enemy_tile := level.tile_of(level.enemy.global_position)
	for item in level.get_tree().get_nodes_in_group("world_items"):
		var tile: Vector2i = level.tile_of((item as Node2D).global_position)
		assert_ne(tile, player_tile)
		assert_ne(tile, enemy_tile)
