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


func test_occludes_extent_ceiling_for_an_entity_resting_at_the_adjacent_tiles_own_centre() -> void:
	var wall_tile := Vector2i(2, 3)
	# tile (2,4) is the tile south of the wall; resting centre: y=(4*48)+24=216.
	var resting_position := Vector2(120.0, 216.0)

	assert_true(MazeRenderer.wall_occludes_extent_ceiling(wall_tile, resting_position, 24.0, TILE_SIZE, OVERDRAW))


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


func test_set_fade_focus_stores_the_position() -> void:
	var renderer := _make_renderer()

	renderer.set_fade_focus(Vector2(100.0, 200.0))

	assert_eq(renderer.fade_focus_position, Vector2(100.0, 200.0))


func test_defaults_to_a_fade_focus_that_never_occludes_anything() -> void:
	var renderer := _make_renderer()

	# The default must never accidentally fade a wall before Level ever
	# calls set_fade_focus() -- Vector2.INF can't fall inside any tile's
	# finite x range, so wall_occludes_position() always returns false.
	assert_false(MazeRenderer.wall_occludes_position(Vector2i(1, 1), renderer.fade_focus_position, 48, 16.0))


func test_draw_does_not_error_with_walls_and_a_fade_focus_present() -> void:
	var renderer := _make_renderer()
	renderer.set_fade_focus(Vector2(24.0, 24.0))

	await get_tree().process_frame

	assert_true(true, "reached this point without erroring")


func test_draw_does_not_error_on_ceiling_plane_with_walls_and_a_fade_focus() -> void:
	var renderer := _make_renderer()
	renderer.set_active_plane(Level.Layer.CEILING)
	renderer.set_fade_focus(Vector2(24.0, 24.0))

	await get_tree().process_frame

	assert_true(true, "reached this point without erroring")
