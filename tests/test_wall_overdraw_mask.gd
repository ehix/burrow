extends GutTest
## WallOverdrawMask (tunnel visual rework Phase 2 follow-up, playtest
## finding): a wall's overdraw silhouette is supposed to occlude whatever's
## standing in the tile it pokes into, but Level.tscn's sibling draw order
## means Entities always paints over Renderer's walls regardless -- this
## repaints just the overlapping patches on top of Entities so a spider or
## Centipede segment actually disappears behind the wall's silhouette. See
## the class's own doc comment for why the player is deliberately excluded.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _mask_of(level: Level) -> WallOverdrawMask:
	return level.get_node("OverdrawMask") as WallOverdrawMask


func test_wall_tile_for_ground_plane_is_the_tile_south_of_the_entity() -> void:
	var wall_tile := WallOverdrawMask.wall_tile_for(Vector2i(2, 3), Level.Layer.GROUND)
	assert_eq(wall_tile, Vector2i(2, 4))


func test_wall_tile_for_ceiling_plane_is_the_tile_north_of_the_entity() -> void:
	var wall_tile := WallOverdrawMask.wall_tile_for(Vector2i(2, 3), Level.Layer.CEILING)
	assert_eq(wall_tile, Vector2i(2, 2))


func test_occludable_entities_excludes_the_player() -> void:
	var level := _make_level()

	var entities := _mask_of(level)._occludable_entities()

	assert_false(entities.has(level.player), "the player is never occluded this way -- see class doc comment")


func test_occludable_entities_includes_the_enemy() -> void:
	var level := _make_level()

	var entities := _mask_of(level)._occludable_entities()

	assert_true(entities.has(level.enemy))


func test_occludable_entities_includes_every_live_centipede_segment() -> void:
	var level := _make_level()
	for node in level.get_tree().get_nodes_in_group("centipedes"):
		node.free()
	var centipede := Centipede.new()
	level.add_child(centipede)
	centipede.bind_level(level)
	centipede.spawn_at([Vector2i(1, 1), Vector2i(1, 2)])

	var entities := _mask_of(level)._occludable_entities()

	for segment in centipede.get_segments():
		assert_true(entities.has(segment))


func test_occludable_entities_includes_every_live_express_rider_segment() -> void:
	var level := _make_level()
	var rider := CentipedeExpressRider.new()
	level.add_child(rider)
	rider.bind_level(level)
	rider.start_run(Vector2i(1, 3), Vector2i.RIGHT)

	var entities := _mask_of(level)._occludable_entities()

	for segment in rider.get_segments():
		assert_true(entities.has(segment))


func test_draw_does_not_error_with_an_enemy_inside_a_walls_overdraw_band() -> void:
	var level := _make_level()
	var wall_tile := Vector2i(2, 2)
	level.maze.set_wall(wall_tile.x, wall_tile.y)
	var entity_tile := Vector2i(2, 1) # north of the wall -- ground-plane overdraw pokes here
	level.enemy.global_position = level.tile_centre(entity_tile)

	await level.get_tree().process_frame

	assert_true(true, "reached this point without erroring")


## Regression guard for the playtest finding wall_occludes_extent() fixes:
## an entity resting at its own tile's centre (level.tile_centre(), exactly
## where GridMover always leaves it -- never at the wall's exact edge) must
## still be detected as occluded. The point-based check this replaced never
## caught this: the "doesn't error" test above used this same resting
## position all along and stayed green throughout, because it only ever
## asserted "no crash," never "was actually occluded."
func test_a_naturally_resting_enemy_is_actually_detected_as_occluded() -> void:
	var level := _make_level()
	var wall_tile := Vector2i(2, 2)
	var entity_tile := Vector2i(2, 1) # north of the wall -- ground-plane overdraw pokes here
	var resting_position := level.tile_centre(entity_tile)

	var occludes := MazeRenderer.wall_occludes_extent(
		wall_tile, resting_position, WallOverdrawMask.ENTITY_VISUAL_HALF_EXTENT,
		Level.TILE_SIZE, level._renderer.wall_overdraw_height)

	assert_true(occludes, "a normally-resting entity's sprite reaches into the band even though its centre point doesn't")


func test_draw_does_not_error_on_ceiling_plane_with_a_centipede_segment_present() -> void:
	var level := _make_level()
	level._renderer.set_active_plane(Level.Layer.CEILING)
	for node in level.get_tree().get_nodes_in_group("centipedes"):
		node.free()
	var centipede := Centipede.new()
	level.add_child(centipede)
	centipede.bind_level(level)
	centipede.spawn_at([Vector2i(2, 2)])

	await level.get_tree().process_frame

	assert_true(true, "reached this point without erroring")
