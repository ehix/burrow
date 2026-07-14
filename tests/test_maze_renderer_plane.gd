extends GutTest
## MazeRenderer's per-plane wall orientation (tunnel visual rework Phase 2):
## _active_plane now drives which way a wall's front face renders (see
## _draw_wall_ground()/_draw_wall_ceiling()) rather than a floor recolor --
## floor rendering moved to FloorRenderer/GroundLayer, which handles "which
## plane am I on" via dimming instead (see test_ground_layer.gd,
## test_level_plane_focus.gd).

func _make_renderer() -> MazeRenderer:
	var renderer := MazeRenderer.new()
	add_child_autofree(renderer)
	var maze := MazeGenerator.generate(3, 3, 1)
	renderer.setup(maze, 48)
	return renderer


func test_defaults_to_ground_plane() -> void:
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
