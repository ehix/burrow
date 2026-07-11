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


func test_world_items_never_land_on_a_pit_tile() -> void:
	var level := _make_level()
	for item in level.get_tree().get_nodes_in_group("world_items"):
		(item as Node2D).free()

	var player_tile := level.tile_of(level.player.global_position)
	var enemy_tile := level.tile_of(level.enemy.global_position)
	var safe_cell: Vector2i = level.maze.open_cells()[0]
	for cell in level.maze.open_cells():
		if cell != player_tile and cell != enemy_tile:
			safe_cell = cell
			break
	for cell in level.maze.open_cells():
		if cell == player_tile or cell == enemy_tile or cell == safe_cell:
			continue
		level.set_pit_at(cell, true)

	level._seed_world_items()

	for item in level.get_tree().get_nodes_in_group("world_items"):
		var tile: Vector2i = level.tile_of((item as Node2D).global_position)
		assert_eq(tile, safe_cell, "every open, non-spawn tile except one was blocked off as a pit")


func test_seeded_items_are_always_pickups_not_bare_lure_pulses() -> void:
	var level := _make_level()
	var items := level.get_tree().get_nodes_in_group("world_items")
	assert_gt(items.size(), 0, "sanity: seeding actually produced items")
	for item in items:
		assert_true(item is WorldItemPickup,
			"Lure is now picked up like every other item, never spawned pre-active as a bare LurePulse")
