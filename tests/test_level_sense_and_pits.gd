extends GutTest
## Level's SenseSkill outline reveal and natural pit seeding (design §4 and §7).


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_set_sense_outline_ghosts_entities_within_radius() -> void:
	var level := _make_level()
	level.player.global_position = Vector2(100, 100)
	var player_sprite := level.player.get_node("Sprite") as Sprite2D

	level.set_sense_outline(true, 50.0)

	var ghost: Sprite2D = level._sense_outlined.get(level.player)
	assert_not_null(ghost, "the player is always within its own sense radius")
	assert_eq(ghost.get_parent(), level._sense_layer, "ghosts live on the un-darkened layer, not under the real entity")
	assert_eq(ghost.texture, player_sprite.texture, "the ghost mirrors the real sprite's texture")
	var mat := ghost.material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.get_shader_parameter("outline_enabled"))
	assert_eq(mat.get_shader_parameter("body_alpha"), 0.0, "only the silhouette shows — the real body stays hidden")


func test_set_sense_outline_skips_entities_outside_radius() -> void:
	var level := _make_level()
	level.player.global_position = Vector2(0, 0)
	level.enemy.global_position = Vector2(1000, 1000) # far outside any reasonable radius

	level.set_sense_outline(true, 50.0)

	assert_false(level._sense_outlined.has(level.enemy), "an entity far outside the radius never gets a ghost")


func test_set_sense_outline_updates_as_the_player_moves_closer() -> void:
	var level := _make_level()
	level.player.global_position = Vector2(0, 0)
	level.enemy.global_position = Vector2(1000, 1000)
	level.set_sense_outline(true, 50.0)

	level.player.global_position = Vector2(990, 990) # now within radius of the enemy
	level._process(0.016)

	assert_true(level._sense_outlined.has(level.enemy), "entering radius spawns a ghost")


func test_set_sense_outline_ghost_tracks_the_real_entitys_movement() -> void:
	var level := _make_level()
	level.player.global_position = Vector2(0, 0)
	level.set_sense_outline(true, 500.0)
	var ghost: Sprite2D = level._sense_outlined[level.player]

	level.player.global_position = Vector2(200, 150)
	level._process(0.016)

	assert_eq(ghost.global_position, level.player.get_node("Sprite").global_position)


func test_set_sense_outline_false_clears_everything() -> void:
	var level := _make_level()
	level.player.global_position = Vector2(0, 0)
	level.set_sense_outline(true, 500.0)
	assert_true(level._sense_outlined.has(level.player))

	level.set_sense_outline(false)

	assert_true(level._sense_outlined.is_empty())


func test_set_sense_outline_traces_wall_boundary_within_radius() -> void:
	var level := _make_level()
	var wall_tile: Vector2i = level._wall_nodes.keys()[0]
	var wall_pos := level.centre_of(wall_tile)
	level.player.global_position = wall_pos # right on top of a wall tile's centre

	level.set_sense_outline(true, 10.0)

	assert_true(level._sense_structure_outline.wall_tiles.has(wall_tile))

	level.set_sense_outline(false)
	assert_true(level._sense_structure_outline.wall_tiles.is_empty())


func test_set_sense_outline_traces_pit_boundary_within_radius() -> void:
	var level := _make_level()
	var pit_tile := Vector2i(4, 4)
	while not level.maze.is_open(pit_tile.x, pit_tile.y): # find an open tile near the centre
		pit_tile += Vector2i(1, 0)
	level.set_pit_at(pit_tile, true)
	level.player.global_position = level.centre_of(pit_tile)

	level.set_sense_outline(true, 10.0)

	assert_true(level._sense_structure_outline.pit_tiles.has(pit_tile))


func test_set_sense_outline_boxes_a_nearby_world_item() -> void:
	var level := _make_level()
	var pickup: WorldItemPickup = preload("res://entities/items/world_item_pickup.tscn").instantiate()
	level.add_child(pickup)
	pickup.global_position = level.player.global_position

	level.set_sense_outline(true, 50.0)

	assert_true(level._sense_point_highlights.has(pickup))
	var outline: Node2D = level._sense_point_highlights[pickup]
	assert_eq(outline.get_parent(), level._sense_layer, "outlines live on the un-darkened layer, not under the entity")

	level.set_sense_outline(false)
	assert_false(level._sense_point_highlights.has(pickup))


func test_set_sense_outline_boxes_a_nearby_earthworm() -> void:
	var level := _make_level()
	var worm: Earthworm = preload("res://entities/earthworm/earthworm.tscn").instantiate()
	level.add_child(worm)
	worm.global_position = level.player.global_position

	level.set_sense_outline(true, 50.0)

	assert_true(level._sense_point_highlights.has(worm))


func test_set_sense_outline_outlines_a_nearby_trap() -> void:
	var level := _make_level()
	var trap: WebTrap = preload("res://entities/web/web_trap.tscn").instantiate()
	level.add_child(trap)
	trap.global_position = level.player.global_position

	level.set_sense_outline(true, 50.0)

	var ghost: Sprite2D = level._sense_outlined.get(trap)
	assert_not_null(ghost, "WebTrap's sprite is named Visual, not Sprite — must still be found")
	var mat := ghost.material as ShaderMaterial
	assert_not_null(mat)
	assert_true(mat.get_shader_parameter("outline_enabled"))


func test_sense_layer_is_not_affected_by_canvas_modulate() -> void:
	var level := _make_level()
	assert_true(level._sense_layer is CanvasLayer)
	assert_true(level._sense_layer.follow_viewport_enabled,
		"must track the camera/world position, not sit fixed on screen like a HUD")


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
