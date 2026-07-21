extends GutTest
## WallOverdrawMask (tunnel visual rework Phase 2 follow-up, playtest
## finding): a wall's overdraw silhouette is supposed to occlude whatever's
## standing in the tile it pokes into, but Level.tscn's sibling draw order
## means Entities always paints over Renderer's walls regardless -- this
## repaints just the overlapping patches on top of Entities so a spider,
## Centipede segment, or Blockade actually disappears behind the wall's
## silhouette. The player gets the exact same repaint as everyone else, at
## the exact same alpha -- no per-entity special case at all. What alpha
## that is depends only on the wall tile's own distance from MazeRenderer's
## fade centre (normally the player's own tile) -- see the class's own doc
## comment and _paint_color_for().

const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")


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


## Playtest finding: Blockade is parented under Entities exactly like every
## other occludable entity (BlockadeSkill._spawn_parent()), so without this
## it was only ever repainted "by accident" on a tick some OTHER entity's
## own straddle happened to also claim the exact same wall_tile -- not
## reliably, the way Player/Enemy/Centipede segments always are.
func test_occludable_entities_includes_a_live_blockade() -> void:
	var level := _make_level()
	var blockade: Blockade = BlockadeScene.instantiate()
	level.add_child(blockade)

	var entities := _mask_of(level)._occludable_entities()

	assert_true(entities.has(blockade))


## End-to-end confirmation, not just group membership: a Blockade resting
## naturally in a wall's overdraw band (level.tile_centre(), exactly where
## it's placed -- see BlockadeSkill._on_activate()) is actually detected as
## occluded, mirroring test_a_naturally_resting_enemy_is_actually_detected_
## as_occluded() above but through the full _occluded_wall_tile_colors()
## pipeline rather than just the underlying wall_occludes_extent() check.
func test_a_naturally_placed_blockade_gets_occluded_by_the_wall_above_it() -> void:
	var level := _make_level()
	var wall_tile := Vector2i(2, 2)
	level.maze.set_wall(wall_tile.x, wall_tile.y)
	var blockade_tile := Vector2i(2, 1) # north of the wall -- ground-plane overdraw pokes here
	level.maze.set_open(blockade_tile.x, blockade_tile.y)
	# Well out of range of this wall_tile's own check -- isolates the
	# assertion to the blockade itself, not a coincidental player/enemy
	# straddle from level.build()'s own random spawn placement.
	level.player.global_position = level.tile_centre(Vector2i(50, 50))
	level.enemy.global_position = level.tile_centre(Vector2i(51, 51))
	var blockade: Blockade = BlockadeScene.instantiate()
	level.add_child(blockade)
	blockade.global_position = level.tile_centre(blockade_tile)

	var colors: Dictionary = _mask_of(level)._occluded_wall_tile_colors()

	assert_true(colors.has(wall_tile), "the wall directly above the blockade repaints over it")


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


## _paint_color_for() no longer takes an entity at all -- a wall tile's
## repaint color depends only on that tile's own position, via MazeRenderer.
## overdraw_alpha_for() (see this file's class doc comment for why the old
## per-entity-type check was replaced). With no fade centre set yet (the
## state before Level's first _process() call), every tile reads at full
## opacity.
func test_paint_color_for_defaults_to_full_opacity_without_a_fade_center() -> void:
	var level := _make_level()

	var color: Color = _mask_of(level)._paint_color_for(Vector2i(2, 2))

	assert_eq(color, level._renderer.tinted_wall_top_face_color())


func test_paint_color_for_uses_the_renderers_live_alpha_at_that_tile() -> void:
	var level := _make_level()
	var wall_tile := Vector2i(2, 2)
	var entity_tile := Vector2i(2, 1) # north of the wall -- ground-plane overdraw pokes here
	level.maze.set_open(entity_tile.x, entity_tile.y) # pin it open -- poked_into_tile_is_open() needs this, not left to the random maze's luck
	level._renderer.set_fade_center(entity_tile)
	level._renderer.wall_fade_min_alpha = 0.25

	var color: Color = _mask_of(level)._paint_color_for(wall_tile)

	assert_eq(color.a, level._renderer.wall_top_face_color.a * 0.25,
		"the wall tile directly adjacent to the fade centre should read at wall_fade_min_alpha")


## Playtest ask: the player should be occluded exactly like every other
## entity when far from the fade centre -- no permanent softening just for
## being the player. Sets the fade centre far away from the wall in
## question so no distance-based fade should apply here at all.
func test_player_is_fully_occluded_by_a_wall_far_from_the_fade_center() -> void:
	var level := _make_level()
	var wall_tile := Vector2i(2, 2)
	level.maze.set_wall(wall_tile.x, wall_tile.y)
	var entity_tile := Vector2i(2, 1) # north of the wall -- ground-plane overdraw pokes here
	level.maze.set_open(entity_tile.x, entity_tile.y) # pin it open, not left to the random maze's luck
	level.player.global_position = level.tile_centre(entity_tile)
	level._renderer.set_fade_center(Vector2i(50, 50)) # far away -- no fade should reach here

	var colors: Dictionary = _mask_of(level)._occluded_wall_tile_colors()

	assert_eq(colors[wall_tile], level._renderer.tinted_wall_top_face_color(),
		"the player must be fully occluded by a wall far from the fade centre, exactly like every other entity")


## Complement to the test above: a wall right next to the fade centre softens
## for ANY entity standing in it, not just the player -- proving the fade is
## tied to the wall's own position, not to entity type (see this file's
## class doc comment).
func test_wall_tile_softens_near_the_fade_center_regardless_of_which_entity_is_there() -> void:
	var level := _make_level()
	var wall_tile := Vector2i(2, 2)
	level.maze.set_wall(wall_tile.x, wall_tile.y)
	var entity_tile := Vector2i(2, 1) # north of the wall -- ground-plane overdraw pokes here
	level.maze.set_open(entity_tile.x, entity_tile.y) # pin it open, not left to the random maze's luck
	level.enemy.global_position = level.tile_centre(entity_tile)
	level._renderer.set_fade_center(entity_tile) # simulate the player standing right there

	var colors: Dictionary = _mask_of(level)._occluded_wall_tile_colors()

	assert_lt(colors[wall_tile].a, level._renderer.wall_top_face_color.a,
		"a wall right next to the fade centre should soften even for the Enemy, not only the player")


## Playtest finding: an entity resting normally (dead-centre in its own
## tile -- exactly where GridMover always leaves it) makes _straddled_
## columns() check both its own column AND one neighbor, by design (see
## that function's own doc comment). When that neighbor column's wall_tile
## has ANOTHER wall stacked immediately behind it (poked_into_tile_is_open()
## false for it), repainting it at all -- regardless of alpha -- silently
## overwrote that other wall's own front-face cap, because this repaint
## runs after Entities, after MazeRenderer already resolved that same rect
## in the stacked wall's favor within its own _draw(). Confirmed via a real
## rendering probe: the cap tile came back painted wall_top_face_color
## (the light color) where wall_front_face_color (the dark cap) belonged.
func test_occluded_wall_tile_colors_never_repaints_a_straddle_neighbor_that_would_overwrite_a_different_walls_cap() -> void:
	var level := _make_level()
	level._renderer.set_active_plane(Level.Layer.CEILING)
	var entity_tile := Vector2i(2, 3)
	level.maze.set_open(entity_tile.x, entity_tile.y)
	level.maze.set_wall(2, 2) # directly north of the entity -- legitimate occlusion
	level.maze.set_wall(3, 2) # straddle-adjacent, same row -- the spurious target
	level.maze.set_wall(3, 3) # (3,2)'s own poked-into tile is ALSO a wall
	level.player.global_position = level.tile_centre(entity_tile)

	var colors: Dictionary = _mask_of(level)._occluded_wall_tile_colors()

	assert_true(colors.has(Vector2i(2, 2)), "the wall directly occluding the entity must still repaint")
	assert_false(colors.has(Vector2i(3, 2)),
		"a straddle-adjacent wall whose own poked-into tile is ALSO a wall must never repaint")


## Ground-plane mirror of the test above -- poked-into flips to north.
func test_occluded_wall_tile_colors_never_repaints_a_straddle_neighbor_on_ground_plane_either() -> void:
	var level := _make_level()
	var entity_tile := Vector2i(2, 1)
	level.maze.set_open(entity_tile.x, entity_tile.y)
	level.maze.set_wall(2, 2) # directly south of the entity -- legitimate occlusion
	level.maze.set_wall(3, 2) # straddle-adjacent, same row -- the spurious target
	level.maze.set_wall(3, 1) # (3,2)'s own poked-into tile (north) is ALSO a wall
	level.player.global_position = level.tile_centre(entity_tile)

	var colors: Dictionary = _mask_of(level)._occluded_wall_tile_colors()

	assert_true(colors.has(Vector2i(2, 2)), "the wall directly occluding the entity must still repaint")
	assert_false(colors.has(Vector2i(3, 2)),
		"a straddle-adjacent wall whose own poked-into tile is ALSO a wall must never repaint")


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


## Regression: a half_extent wider than half a tile (real since
## MazeRenderer.ENTITY_VISUAL_HALF_EXTENT was bumped to 28 for the bigger
## NSWE sprites) makes the window wide enough to span 3 columns, not just 2
## -- the old [left_col, right_col]-only implementation silently dropped
## the middle column, leaving a wall tile the sprite genuinely still
## overlaps unchecked (caught via test_a_naturally_placed_blockade_gets_
## occluded_by_the_wall_above_it starting to fail after that bump).
func test_straddled_columns_includes_the_middle_column_when_the_extent_spans_three() -> void:
	# x=120 (dead centre of column 2, [96,144)) with a 28px half-extent:
	# window is [92,148), reaching into column 1 ([48,96)) on the left and
	# column 3 ([144,192)) on the right, with column 2 itself in between.
	var columns := WallOverdrawMask._straddled_columns(120.0, 28.0, 48)

	assert_eq(columns, [1, 2, 3])


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


## Regression guard: bumping Player/Enemy's SPRITE_TARGET_EXTENT_PX (the
## normalized on-screen sprite footprint) without also bumping this constant
## left leg tips unmasked -- visibly poking through a wall's overdraw
## silhouette even while the entity itself is correctly hidden by fog-of-war,
## since WallOverdrawMask only repaints out to this assumed half-extent.
func test_entity_visual_half_extent_covers_the_current_sprite_size() -> void:
	assert_true(WallOverdrawMask.ENTITY_VISUAL_HALF_EXTENT >= Player.SPRITE_TARGET_EXTENT_PX / 2.0,
		"must reach at least as far as half the player's own normalized sprite size")
	assert_true(WallOverdrawMask.ENTITY_VISUAL_HALF_EXTENT >= Enemy.SPRITE_TARGET_EXTENT_PX / 2.0,
		"must reach at least as far as half the enemy's own normalized sprite size")


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
