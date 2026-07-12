extends GutTest
## MazeRenderer's per-plane floor color (ceiling/plane mechanics rework):
## replaces the old ceiling sprite tint with a floor re-color, so the ground
## renders in floor_color and the ceiling in ceiling_floor_color — the
## roadmap's literal "floor re-colors (not spider)" requirement.

func _make_renderer() -> MazeRenderer:
	var renderer := MazeRenderer.new()
	add_child_autofree(renderer)
	var maze := MazeGenerator.generate(3, 3, 1)
	renderer.setup(maze, 48)
	return renderer


func test_defaults_to_ground_floor_color() -> void:
	var renderer := _make_renderer()

	assert_eq(renderer._active_plane, Level.Layer.GROUND)


func test_set_active_plane_to_ceiling_switches_the_tracked_plane() -> void:
	var renderer := _make_renderer()

	renderer.set_active_plane(Level.Layer.CEILING)

	assert_eq(renderer._active_plane, Level.Layer.CEILING)


func test_set_active_plane_back_to_ground_switches_back() -> void:
	var renderer := _make_renderer()
	renderer.set_active_plane(Level.Layer.CEILING)

	renderer.set_active_plane(Level.Layer.GROUND)

	assert_eq(renderer._active_plane, Level.Layer.GROUND)


func test_floor_and_ceiling_colors_are_distinct() -> void:
	var renderer := _make_renderer()

	assert_ne(renderer.floor_color, renderer.ceiling_floor_color)
