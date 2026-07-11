extends GutTest
## Level's SenseSkill x-ray hook and natural pit seeding (design §4 and §7).


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_set_sense_active_hides_wall_occluders() -> void:
	var level := _make_level()
	var any_occluder: Node = null
	for nodes in level._wall_nodes.values():
		any_occluder = nodes.get("occluder")
		break
	assert_not_null(any_occluder, "the freshly-built level should have at least one wall")

	level.set_sense_active(true)
	assert_false(any_occluder.visible, "wall occluders stop blocking light while sense is active")

	level.set_sense_active(false)
	assert_true(any_occluder.visible, "occluders are restored once sense ends")


func test_set_sense_outline_toggles_the_shader_on_every_spider_and_larva() -> void:
	var level := _make_level()
	var player_sprite := level.player.get_node("Sprite") as CanvasItem
	var enemy_sprite := level.enemy.get_node("Sprite") as CanvasItem

	level.set_sense_outline(true)
	var player_mat := player_sprite.material as ShaderMaterial
	var enemy_mat := enemy_sprite.material as ShaderMaterial
	assert_not_null(player_mat)
	assert_true(player_mat.get_shader_parameter("outline_enabled"))
	assert_not_null(enemy_mat)
	assert_true(enemy_mat.get_shader_parameter("outline_enabled"))

	level.set_sense_outline(false)
	assert_false(player_mat.get_shader_parameter("outline_enabled"))
	assert_false(enemy_mat.get_shader_parameter("outline_enabled"))


func test_build_seeds_natural_pits_away_from_both_spawns() -> void:
	var level := _make_level()
	var pit_count := 0
	var player_tile := level.tile_of(level.player.global_position)
	var enemy_tile := level.tile_of(level.enemy.global_position)
	for cell in level.maze.open_cells():
		if level.maze.is_pit(cell.x, cell.y):
			pit_count += 1
			assert_ne(cell, player_tile, "a natural pit never lands on the player's spawn tile")
			assert_ne(cell, enemy_tile, "a natural pit never lands on the enemy's spawn tile")
	assert_eq(pit_count, Level.NATURAL_PIT_COUNT)
