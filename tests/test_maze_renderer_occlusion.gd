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
