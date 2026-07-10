extends GutTest
## Larva hazard-blocking (playtest fix, sub-project C): a pit/flood tile
## blocks a larva's ground stepping exactly like a wall does, mirroring
## Player._blocked()'s existing ground-plane check (see
## test_player_ceiling_traversal.gd, whose _make_level() pattern this
## reuses). Building a real, fully-built Level also proves
## Level._spawn_larva_at() actually wires bind_level() — if it didn't, the
## spawned larva's _level would be null and the blocked-check would
## silently fall through to open ground instead of catching the pit.

const LarvaScene := preload("res://entities/larva/larva.tscn")


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _first_larva(level: Level) -> Larva:
	return level.get_tree().get_nodes_in_group("larvae")[0] as Larva


func test_a_pit_blocks_a_spawned_larvas_ground_stepping() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y) # guarantee open regardless of maze layout
	level.set_pit_at(ahead, true)

	assert_true(larva._blocked(Vector2i(1, 0)), "a pit blocks the larva's ground stepping")


func test_open_ground_does_not_block_a_spawned_larva() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)

	assert_false(larva._blocked(Vector2i(1, 0)), "open ground never blocks")


func test_a_wall_blocks_a_spawned_larva() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var wall := tile + Vector2i(1, 0)
	level.maze.set_wall(wall.x, wall.y)

	assert_true(larva._blocked(Vector2i(1, 0)), "a wall blocks the larva too")


func test_a_bare_larva_never_bound_to_a_level_falls_through_to_test_move() -> void:
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)

	# No _level set at all — must not error. With no physical collider
	# nearby, test_move reports open (not blocked).
	assert_false(larva._blocked(Vector2i(1, 0)))
