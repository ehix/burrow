extends GutTest
## Player's ceiling-plane wiring (design §1): toggling the plane flips
## PlaneComponent.current_plane, and Player._blocked() lets a pit stop ground
## movement while the ceiling passes straight over the same tile — the
## "ceiling bypasses ground hazards" clause from the spec.

const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")


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


func test_a_blockade_blocks_the_player_from_stepping_onto_its_tile() -> void:
	# Playtest bug: the player could walk straight through their own placed
	# Blockade. Locks in that _blocked() (and therefore GridMover.try_step())
	# actually refuses the step, on both planes, not just that Level.is_blocked()
	# reports it in isolation.
	var level := _make_level()
	var player := level.player as Player
	var tile := level.tile_of(player.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)
	level.set_pit_at(ahead, false)
	var blockade: Blockade = BlockadeScene.instantiate()
	add_child_autofree(blockade)
	blockade.global_position = level.centre_of(ahead)

	assert_true(player._blocked(Vector2i(1, 0)), "a blockade blocks ground stepping")
	var mover := player.get_node_or_null("GridMover") as GridMover
	var started := mover.try_step(Vector2i(1, 0))
	assert_false(started, "the step never begins — the player can't walk onto the blockade's tile")
	assert_eq(level.tile_of(player.global_position), tile, "the player never leaves their own tile")

	player._plane.transition() # -> CEILING
	assert_true(player._blocked(Vector2i(1, 0)), "the same blockade blocks the ceiling too")
