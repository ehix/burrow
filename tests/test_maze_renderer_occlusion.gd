extends GutTest
## MazeRenderer.wall_occludes_position() (tunnel faux-3D rework, Phase 1):
## a wall's rendered block pokes `overdraw` pixels above its own tile into
## the tile north of it (see maze_renderer.gd's own doc comment) -- this is
## the pure "would this wall's overdraw currently hide something standing
## at `position`" check, kept scene-tree-free so it's directly unit-
## testable. Uses tile_size=48, overdraw=16 throughout to match
## MazeRenderer's own defaults.

const TILE_SIZE := 48
const OVERDRAW := 16.0


func test_occludes_a_position_in_the_overdraw_band_directly_above_it() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,3) spans x=[96,144], y=[144,192]; its overdraw band is
	# y=[144-16, 144] = [128, 144] in the tile north of it (2,2).
	var position := Vector2(120.0, 136.0)

	assert_true(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_a_position_above_the_overdraw_band() -> void:
	var wall_tile := Vector2i(2, 3)
	# y=120 is further north than the 16px overdraw band reaches (128-144).
	var position := Vector2(120.0, 120.0)

	assert_false(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_a_position_south_of_the_wall() -> void:
	var wall_tile := Vector2i(2, 3)
	# y=160 is inside/south of the wall's own tile -- the front face only
	# ever reads as a cliff facing north, never occludes anything south.
	var position := Vector2(120.0, 160.0)

	assert_false(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_a_position_outside_its_column() -> void:
	var wall_tile := Vector2i(2, 3)
	# Same y as the first (passing) test, but x=200 is a full tile-width
	# outside wall_tile's own column (x=[96,144]).
	var position := Vector2(200.0, 136.0)

	assert_false(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_occludes_at_the_exact_tile_top_boundary() -> void:
	var wall_tile := Vector2i(2, 3)
	var position := Vector2(120.0, 144.0) # exactly the wall's own tile_top

	assert_true(MazeRenderer.wall_occludes_position(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_occludes_ceiling_a_position_in_the_overdraw_band_directly_below_it() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,3) spans x=[96,144], y=[144,192]; its ceiling overdraw band is
	# y=[192, 192+16] = [192, 208] in the tile south of it (2,4).
	var position := Vector2(120.0, 200.0)

	assert_true(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_ceiling_a_position_below_the_overdraw_band() -> void:
	var wall_tile := Vector2i(2, 3)
	# y=220 is further south than the 16px overdraw band reaches (192-208).
	var position := Vector2(120.0, 220.0)

	assert_false(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_ceiling_a_position_north_of_the_wall() -> void:
	var wall_tile := Vector2i(2, 3)
	# y=160 is inside/north of the wall's own tile -- the ceiling front face
	# only ever reads as hanging down, never occludes anything north of it.
	var position := Vector2(120.0, 160.0)

	assert_false(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_ceiling_a_position_outside_its_column() -> void:
	var wall_tile := Vector2i(2, 3)
	# Same y as the first (passing) test, but x=200 is a full tile-width
	# outside wall_tile's own column (x=[96,144]).
	var position := Vector2(200.0, 200.0)

	assert_false(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))


func test_occludes_ceiling_at_the_exact_tile_bottom_boundary() -> void:
	var wall_tile := Vector2i(2, 3)
	var position := Vector2(120.0, 192.0) # exactly the wall's own tile_bottom

	assert_true(MazeRenderer.wall_occludes_position_ceiling(wall_tile, position, TILE_SIZE, OVERDRAW))


# --- wall_occludes_extent()/_ceiling() (playtest fix: GridMover always rests
# an entity at its own tile's centre -- 24px from any edge at this game's
# 48px tile size -- so a plain point check (wall_occludes_position) never
# fires for a resting entity even though its ~40-48px sprite visibly
# reaches within a few pixels of the wall's edge either way; a WallOverdrawMask
# using the point check silently never occluded anything in normal play) ----

func test_occludes_extent_for_an_entity_resting_at_the_adjacent_tiles_own_centre() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,2) is the tile north of the wall; GridMover would rest an
	# entity there at its own tile centre: x=120, y=(2*48)+24=120.
	var resting_position := Vector2(120.0, 120.0)

	assert_true(MazeRenderer.wall_occludes_extent(wall_tile, resting_position, 24.0, TILE_SIZE, OVERDRAW),
		"a normal resting position must be detected -- this is the exact case the point check missed")


func test_does_not_occlude_extent_for_a_position_and_half_extent_that_cant_reach_the_band() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,1) is two tiles north of the wall -- resting centre y=72, far
	# enough that even a generous half-extent can't reach the overdraw band.
	var far_position := Vector2(120.0, 72.0)

	assert_false(MazeRenderer.wall_occludes_extent(wall_tile, far_position, 24.0, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_extent_outside_the_walls_column() -> void:
	var wall_tile := Vector2i(2, 3)
	var resting_position := Vector2(200.0, 120.0) # same y as the passing test, wrong column

	assert_false(MazeRenderer.wall_occludes_extent(wall_tile, resting_position, 24.0, TILE_SIZE, OVERDRAW))


## Playtest fix: an entity mid-step, straddling a column boundary next to a
## wall run, has its sprite's near edge already inside the neighboring
## column even though its centre x hasn't crossed yet -- a plain column
## containment check (the old x-gate here) rejected that neighbor outright,
## so WallOverdrawMask could only ever repaint whichever single column the
## entity's exact centre currently floor-divided to, leaving the straddling
## half of the sprite unoccluded for a chunk of every step (see
## WallOverdrawMask._straddled_columns()'s own doc comment for the full
## picture -- this test covers just the underlying primitive's new margin).
func test_occludes_extent_for_a_position_straddling_into_the_walls_column() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,2) is the tile north of the wall (x=[96,144]); a position just
	# inside the tile east of that, x=150, is 6px past wall_tile's own right
	# edge (144) -- well within a 24px half-extent, so its sprite still
	# reaches back into wall_tile's column even though its centre doesn't.
	var straddling_position := Vector2(150.0, 120.0)

	assert_true(MazeRenderer.wall_occludes_extent(wall_tile, straddling_position, 24.0, TILE_SIZE, OVERDRAW),
		"a sprite straddling the column boundary must still be checked against the neighboring wall tile")


func test_does_not_occlude_extent_for_a_position_too_far_outside_the_column_to_straddle() -> void:
	var wall_tile := Vector2i(2, 3)
	# x=170 is 26px past wall_tile's right edge (144) -- just outside a 24px
	# half-extent, so this position's sprite genuinely doesn't reach back in.
	var far_position := Vector2(170.0, 120.0)

	assert_false(MazeRenderer.wall_occludes_extent(wall_tile, far_position, 24.0, TILE_SIZE, OVERDRAW))


func test_occludes_extent_ceiling_for_an_entity_resting_at_the_adjacent_tiles_own_centre() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,4) is the tile south of the wall; resting centre: y=(4*48)+24=216.
	var resting_position := Vector2(120.0, 216.0)

	assert_true(MazeRenderer.wall_occludes_extent_ceiling(wall_tile, resting_position, 24.0, TILE_SIZE, OVERDRAW))


func test_occludes_extent_ceiling_for_a_position_straddling_into_the_walls_column() -> void:
	var wall_tile := Vector2i(2, 3)
	var straddling_position := Vector2(150.0, 216.0) # 6px past wall_tile's right edge (144)

	assert_true(MazeRenderer.wall_occludes_extent_ceiling(wall_tile, straddling_position, 24.0, TILE_SIZE, OVERDRAW))


func test_does_not_occlude_extent_ceiling_for_a_position_too_far_south() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,5) is two tiles south of the wall -- resting centre y=264.
	var far_position := Vector2(120.0, 264.0)

	assert_false(MazeRenderer.wall_occludes_extent_ceiling(wall_tile, far_position, 24.0, TILE_SIZE, OVERDRAW))


# --- neither plane ever clips its overdraw for an adjacent pit or flooded
# tile (playtest fix: a hole is meant to partially disappear behind a
# wall's overdraw silhouette, same as anything else in the tile the
# overdraw pokes into -- shrinking the wall's own geometry near a pit
# produced a visible notch instead, see _draw_wall_ground()'s doc comment)
# -- both hand-built mazes below use set_pit() directly, which is also
# exactly how a flooded tile is flagged (Level.set_water_at()), so this
# covers water tiles too, not just natural pits. --------------------------

func test_draw_does_not_error_on_ground_plane_with_a_pit_north_of_a_wall() -> void:
	# Hand-built 1x2 maze (not MazeGenerator's random layout) so the pit at
	# (0,0) is guaranteed to sit directly north of the wall at (0,1) -- the
	# exact adjacency _draw_wall_ground()'s (now-removed) pit clip used to
	# key off.
	var maze := MazeData.new(PackedByteArray([1, 0]), 1, 2)
	maze.set_pit(0, 0, true)
	var renderer := MazeRenderer.new()
	add_child_autofree(renderer)
	renderer.setup(maze, TILE_SIZE)

	await get_tree().process_frame

	assert_true(true, "reached this point without erroring")


func test_draw_does_not_error_on_ceiling_plane_with_a_pit_south_of_a_wall() -> void:
	# Hand-built 1x2 maze (not MazeGenerator's random layout) so the pit at
	# (0,1) is guaranteed to sit directly south of the wall at (0,0) -- the
	# exact adjacency _draw_wall_ceiling()'s (now-removed) pit clip used to
	# key off.
	var maze := MazeData.new(PackedByteArray([0, 1]), 1, 2)
	maze.set_pit(0, 1, true)
	var renderer := MazeRenderer.new()
	add_child_autofree(renderer)
	renderer.setup(maze, TILE_SIZE)
	renderer.set_active_plane(Level.Layer.CEILING)

	await get_tree().process_frame

	assert_true(true, "reached this point without erroring")


func _make_renderer() -> MazeRenderer:
	var renderer := MazeRenderer.new()
	add_child_autofree(renderer)
	var maze := MazeGenerator.generate(3, 3, 1)
	renderer.setup(maze, 48)
	return renderer


## Confirms MazeRenderer still draws without erroring on both planes, with
## no fade centre set yet (the state before Level's first _process() call --
## see set_fade_center()'s own doc comment) -- overdraw_alpha_for() must
## default to full opacity in that state rather than erroring or drawing
## nothing.
func test_draw_does_not_error_on_the_ground_plane() -> void:
	_make_renderer()

	await get_tree().process_frame

	assert_true(true, "reached this point without erroring")


func test_draw_does_not_error_on_the_ceiling_plane() -> void:
	var renderer := _make_renderer()
	renderer.set_active_plane(Level.Layer.CEILING)

	await get_tree().process_frame

	assert_true(true, "reached this point without erroring")


func test_draw_does_not_error_with_a_fade_center_set() -> void:
	var renderer := _make_renderer()
	renderer.set_fade_center(Vector2i(1, 1))

	await get_tree().process_frame

	assert_true(true, "reached this point without erroring")


# --- overdraw_alpha_for_distance()/overdraw_alpha_for() (playtest ask:
# occlude the player exactly like every other entity, but fade nearby wall
# overdraw so the player's own sprite doesn't vanish -- see WallOverdrawMask's
# own doc comment for why this replaced the old per-entity-type special case)
# -----------------------------------------------------------------------

func test_overdraw_alpha_for_distance_is_full_opacity_at_or_beyond_the_radius() -> void:
	assert_eq(MazeRenderer.overdraw_alpha_for_distance(2.0, 2.0, 0.25), 1.0)
	assert_eq(MazeRenderer.overdraw_alpha_for_distance(5.0, 2.0, 0.25), 1.0)


func test_overdraw_alpha_for_distance_is_min_alpha_at_the_centre() -> void:
	assert_eq(MazeRenderer.overdraw_alpha_for_distance(0.0, 2.0, 0.25), 0.25)


func test_overdraw_alpha_for_distance_ramps_linearly_between() -> void:
	# Halfway to the radius (distance=1, radius=2) should read halfway
	# between min_alpha (0.25) and full opacity (1.0): 0.625.
	assert_almost_eq(MazeRenderer.overdraw_alpha_for_distance(1.0, 2.0, 0.25), 0.625, 0.0001)


func test_overdraw_alpha_for_distance_is_full_opacity_when_radius_is_zero_or_negative() -> void:
	# A zero/negative radius means "fading is off" -- must not divide by zero.
	assert_eq(MazeRenderer.overdraw_alpha_for_distance(0.0, 0.0, 0.25), 1.0)
	assert_eq(MazeRenderer.overdraw_alpha_for_distance(0.0, -1.0, 0.25), 1.0)


func test_overdraw_alpha_for_is_full_opacity_before_a_fade_center_is_ever_set() -> void:
	var renderer := _make_renderer()

	assert_eq(renderer.overdraw_alpha_for(Vector2i(0, 0)), 1.0)


func test_overdraw_alpha_for_uses_chebyshev_distance_from_the_fade_center() -> void:
	var renderer := _make_renderer()
	renderer.wall_fade_radius_tiles = 2.0
	renderer.wall_fade_min_alpha = 0.25
	renderer.set_fade_center(Vector2i(5, 5))

	# (6,7) is 2 tiles away on the y axis -- Chebyshev distance is the max of
	# the two axes (max(1,2)=2), matching a square "N tiles out" ring, not a
	# circular one -- exactly at the radius, so still full opacity.
	assert_eq(renderer.overdraw_alpha_for(Vector2i(6, 7)), 1.0)
	# The centre tile itself reads at min_alpha.
	assert_eq(renderer.overdraw_alpha_for(Vector2i(5, 5)), 0.25)
