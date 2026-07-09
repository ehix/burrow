extends GutTest
## Player's ceiling-plane wiring (design §1): toggling the plane flips
## PlaneComponent.current_plane, and Player._blocked() lets a pit stop ground
## movement while the ceiling passes straight over the same tile — the
## "ceiling bypasses ground hazards" clause from the spec.


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_toggle_plane_flips_current_plane() -> void:
	var level := _make_level()
	var player := level.player as Player
	assert_eq(player._plane.current_plane, Level.Layer.GROUND)
	player._plane.transition()
	assert_eq(player._plane.current_plane, Level.Layer.CEILING)
	player._plane.transition()
	assert_eq(player._plane.current_plane, Level.Layer.GROUND)


func test_player_is_bound_to_its_level() -> void:
	var level := _make_level()
	var player := level.player as Player
	assert_eq(player._level, level)
	assert_eq(player._plane.level, level)


func test_a_pit_blocks_ground_movement_but_not_ceiling() -> void:
	var level := _make_level()
	var player := level.player as Player
	var tile := level.tile_of(player.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y) # guarantee open regardless of maze layout
	level.set_pit_at(ahead, true)

	assert_true(player._blocked(Vector2i(1, 0)), "a pit blocks ground stepping")
	player._plane.transition() # -> CEILING
	assert_false(player._blocked(Vector2i(1, 0)), "the ceiling passes over the same pit")


func test_a_wall_blocks_both_planes() -> void:
	var level := _make_level()
	var player := level.player as Player
	var tile := level.tile_of(player.global_position)
	var wall := tile + Vector2i(1, 0)
	level.maze.set_wall(wall.x, wall.y)

	assert_true(player._blocked(Vector2i(1, 0)), "a wall blocks ground stepping")
	player._plane.transition() # -> CEILING
	assert_true(player._blocked(Vector2i(1, 0)), "the same solid rock blocks the ceiling too")
