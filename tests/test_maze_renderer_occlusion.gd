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
