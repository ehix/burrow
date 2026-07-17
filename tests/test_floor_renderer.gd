extends GutTest
## FloorRenderer (tunnel visual rework Phase 2): draws just the maze's open
## floor tiles, split out of MazeRenderer so GroundLayer can dim it
## independently of the (now wall-only) MazeRenderer. No pixel assertions
## -- this project's own established pattern (see test_maze_renderer_plane.gd)
## -- just that setup() doesn't error against a real maze once the engine's
## own redraw cycle actually calls _draw() (never call _draw() directly --
## draw_rect() requires an active redraw pass).

func test_setup_does_not_error_with_a_real_maze() -> void:
	var renderer := FloorRenderer.new()
	add_child_autofree(renderer)
	var maze := MazeGenerator.generate(3, 3, 1)

	renderer.setup(maze, 48)
	await renderer.get_tree().process_frame

	assert_true(true, "reached this point without erroring")
