extends GutTest
## WallOverdrawMask (tunnel visual rework Phase 2 follow-up, playtest
## finding): a wall's overdraw silhouette is supposed to occlude whatever's
## standing in the tile it pokes into, but Level.tscn's sibling draw order
## means Entities always paints over Renderer's walls regardless -- this
## repaints just the overlapping patches on top of Entities so a spider or
## Centipede segment actually disappears behind the wall's silhouette. The
## player gets the same repaint as everyone else (playtest follow-up: it
## used to be skipped entirely here), just at a translucent alpha instead
## of full opacity -- see the class's own doc comment and _paint_color_for().

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


func test_occludable_entities_includes_the_player() -> void:
	var level := _make_level()

	var entities := _mask_of(level)._occludable_entities()

	assert_true(entities.has(level.player), "the player gets the same repaint as everyone else now -- see class doc comment")


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


func test_draw_does_not_error_with_the_player_inside_a_walls_overdraw_band() -> void:
	var level := _make_level()
	var wall_tile := Vector2i(2, 2)
	level.maze.set_wall(wall_tile.x, wall_tile.y)
	var entity_tile := Vector2i(2, 1) # north of the wall -- ground-plane overdraw pokes here
	level.player.global_position = level.tile_centre(entity_tile)

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


## Regression guard for the playtest finding "the player doesn't adhere to
## the partial occlusion rule": a naturally-resting player (level.tile_
## centre(), exactly where GridMover leaves it) must be detected as
## occluded via the exact same call _draw() makes for every other entity --
## mirrors test_a_naturally_resting_enemy_is_actually_detected_as_occluded()
## above, just for the player specifically, now that it's no longer
## excluded from _occludable_entities().
func test_a_naturally_resting_player_is_actually_detected_as_occluded() -> void:
	var level := _make_level()
	var wall_tile := Vector2i(2, 2)
	var entity_tile := Vector2i(2, 1) # north of the wall -- ground-plane overdraw pokes here
	var resting_position := level.tile_centre(entity_tile)

	var occludes := MazeRenderer.wall_occludes_extent(
		wall_tile, resting_position, WallOverdrawMask.ENTITY_VISUAL_HALF_EXTENT,
		Level.TILE_SIZE, level._renderer.wall_overdraw_height)

	assert_true(occludes, "a normally-resting player's sprite reaches into the band even though its centre point doesn't")


## _paint_color_for() is what actually keeps the player from ever being
## fully hidden now that it goes through the same repaint as everyone else
## (playtest ask: the mask should paint over the player just like the enemy,
## but stay translucent so more of the spider still shows through).
func test_paint_color_for_the_player_is_translucent() -> void:
	var level := _make_level()

	var color: Color = _mask_of(level)._paint_color_for(level.player)

	assert_eq(color.a, level._renderer.wall_top_face_color.a * WallOverdrawMask.PLAYER_PAINT_ALPHA)


func test_paint_color_for_the_enemy_is_full_opacity() -> void:
	var level := _make_level()

	var color: Color = _mask_of(level)._paint_color_for(level.enemy)

	assert_eq(color, level._renderer.wall_top_face_color)


## Playtest bug: a centipede segment's own wall overdraw would go nearly
## transparent whenever the player walked near enough to also claim the same
## occluding wall_tile -- _occludable_entities() always lists spiders (the
## player included) before centipede segments, so the old first-wins dedup
## in _draw() let the player's translucent paint silently override a
## full-opacity entity's occlusion for that tile, even though the player's
## own sprite was nowhere near the affected pixels. Using the Enemy here
## (also full-opacity, see test_paint_color_for_the_enemy_is_full_opacity)
## stands in for a centipede segment without the extra scene setup.
func test_occluded_wall_tile_colors_prefers_full_opacity_over_the_players_translucent_paint() -> void:
	var level := _make_level()
	var wall_tile := Vector2i(2, 2)
	level.maze.set_wall(wall_tile.x, wall_tile.y)
	var entity_tile := Vector2i(2, 1) # north of the wall -- ground-plane overdraw pokes here
	var resting_position := level.tile_centre(entity_tile)
	level.player.global_position = resting_position
	level.enemy.global_position = resting_position

	var colors: Dictionary = _mask_of(level)._occluded_wall_tile_colors()

	assert_eq(colors[wall_tile], level._renderer.wall_top_face_color,
		"a full-opacity entity sharing the tile must not have its occlusion diluted by the player's translucent paint")


## Playtest fix: while mid-step, an entity's sprite spans two tile columns
## for most of every step (its half-extent is close to half a tile wide),
## but entity_tile.x -- a single floor-divided column -- only ever names
## ONE of them. _draw() used to check just that one, so as an entity
## crossed a column boundary next to a wall run, only half its sprite was
## ever tested for occlusion at a time -- the other half popped fully
## visible until the exact frame the column flipped, then reversed. See
## MazeRenderer's straddle tests for the underlying primitive this feeds.
func test_straddled_columns_is_a_single_column_when_its_margin_cant_reach_a_boundary() -> void:
	# x=168 is column 3's own centre ([144,192)); a 10px half-extent stays
	# well clear of either edge (134 and 178, both inside [144,192)).
	var columns := WallOverdrawMask._straddled_columns(168.0, 10.0, 48)

	assert_eq(columns, [3])


func test_straddled_columns_includes_both_columns_when_the_sprite_crosses_a_boundary() -> void:
	# x=150 is 6px into column 3 ([144,192)); a 24px half-extent reaches back
	# to 126, still inside column 2's tile ([96,144)) -- floor(150/48)=3 is
	# the entity's own column, but its sprite still visibly overlaps column 2.
	var columns := WallOverdrawMask._straddled_columns(150.0, 24.0, 48)

	assert_true(columns.has(3), "the entity's own column")
	assert_true(columns.has(2), "the neighboring column its sprite still reaches into")
	assert_eq(columns.size(), 2)


## ENTITY_VISUAL_HALF_EXTENT is exactly half a tile wide, so the [x-half,
## x+half) window this checks is exactly as wide as one tile -- meaning it
## can never sit fully inside a single column's bounds no matter where x
## is, including dead centre: floor() treats the window's own upper edge as
## already belonging to the next column. So in production this always
## checks exactly two adjacent columns per entity per frame, never one --
## a deliberate, harmless redundancy (the extra column's wall_tile is
## already drawn identically by MazeRenderer itself whether or not anything
## is standing in it) traded for never missing a genuine straddle.
func test_straddled_columns_with_a_half_tile_extent_always_spans_two_adjacent_columns() -> void:
	var columns := WallOverdrawMask._straddled_columns(72.0, 24.0, 48) # column 1's own exact centre

	assert_eq(columns, [1, 2])


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
