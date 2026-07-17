extends GutTest
## Larva hazard-blocking (playtest fix, sub-project C): a pit/flood tile
## blocks a larva's ground stepping exactly like a wall does, mirroring
## Player._blocked()'s existing ground-plane check (see
## test_player_ceiling_traversal.gd, whose _make_level() pattern this
## reuses). Building a real, fully-built Level also proves
## Level._spawn_larva_at() actually wires bind_level() — if it didn't, the
## spawned larva's _level would be null and the blocked-check would
## silently fall through to open ground instead of catching the pit.

const LarvaScene := preload("res://entities/larva/larva.tscn")


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _first_larva(level: Level) -> Larva:
	return level.get_tree().get_nodes_in_group("larvae")[0] as Larva


func test_a_pit_blocks_a_spawned_larvas_ground_stepping() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y) # guarantee open regardless of maze layout
	level.set_pit_at(ahead, true)

	assert_true(larva._blocked(Vector2i(1, 0)), "a pit blocks the larva's ground stepping")


func test_open_ground_does_not_block_a_spawned_larva() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)

	assert_false(larva._blocked(Vector2i(1, 0)), "open ground never blocks")


func test_a_wall_blocks_a_spawned_larva() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var wall := tile + Vector2i(1, 0)
	level.maze.set_wall(wall.x, wall.y)

	assert_true(larva._blocked(Vector2i(1, 0)), "a wall blocks the larva too")


func test_a_bare_larva_never_bound_to_a_level_falls_through_to_test_move() -> void:
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)

	# No _level set at all — must not error. With no physical collider
	# nearby, test_move reports open (not blocked).
	assert_false(larva._blocked(Vector2i(1, 0)))


## Playtest fix: a larva can never have walked onto a pit itself (_blocked()
## above already refuses that step exactly like a wall), so spawning is the
## only way one could ever end up sitting on a hole. Both spawn paths must
## skip a pit tile the same way they already skip a spider- or Centipede-
## occupied one.
func test_spawn_larva_at_random_never_lands_on_a_pit() -> void:
	var level := _make_level()
	var player_cell := level.tile_of(level.player.global_position)
	var enemy_cell := level.tile_of(level.enemy.global_position)
	var cells: Array = level.maze.open_cells()
	var safe_cell: Vector2i
	for cell in cells:
		if cell != player_cell and cell != enemy_cell:
			safe_cell = cell
			break
	# Seal every open cell except the two spawns and one deliberately-left-
	# open "safe" cell -- leaving exactly one valid destination proves the
	# new larva actively skipped every pit-sealed alternative, not just that
	# it happened to land somewhere non-pit by chance. (This also kills
	# every pre-existing larva caught on a now-pitted tile via Level.
	# _kill_larvae_at() -- queue_free()'d but not yet actually gone from the
	# group at this synchronous point, hence checking is_queued_for_deletion()
	# below rather than relying on group membership alone.)
	for cell in cells:
		if cell != player_cell and cell != enemy_cell and cell != safe_cell:
			level.set_pit_at(cell, true)

	level._spawn_larva_at_random()

	var new_larva: Larva = null
	for larva in level.get_tree().get_nodes_in_group("larvae"):
		var l := larva as Larva
		if not l.is_queued_for_deletion() and level.tile_of(l.global_position) == safe_cell:
			new_larva = l
			break
	assert_not_null(new_larva, "the only non-pit, unoccupied cell is where the new larva must land")


## Defensive: real build() order seeds natural pits *after* this initial
## batch, so none exist yet in practice -- but calling _spawn_larvae() again
## once pits genuinely do exist (as this test forces) proves the skip isn't
## accidentally tied to that ordering.
func test_spawn_larvae_never_lands_on_a_pit() -> void:
	var level := _make_level()
	var player_cell := level.tile_of(level.player.global_position)
	var enemy_cell := level.tile_of(level.enemy.global_position)
	for cell in level.maze.open_cells():
		if cell != player_cell and cell != enemy_cell:
			level.set_pit_at(cell, true) # seal every open cell but the two reserved spawns
	var before := level.get_tree().get_nodes_in_group("larvae").size()

	level._spawn_larvae([player_cell, enemy_cell])

	var after := level.get_tree().get_nodes_in_group("larvae").size()
	assert_eq(after, before, "every open cell but the two reserved spawns is a pit -- nowhere valid to place a new one")


## Playtest fix: a pit only blocks GROUND movement, but a larva has no
## plane to escape to (unlike a spider, which gets shoved off instead — see
## Level._shove_ground_spiders_off()) -- one standing on the tile the
## instant a pit opens there is killed outright, mirroring
## _destroy_occupants_at()'s identical plain queue_free() for a tile
## turning into a wall.
func test_set_pit_at_kills_a_larva_standing_on_the_new_pit_tile() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)

	level.set_pit_at(tile, true)

	assert_true(larva.is_queued_for_deletion(), "a larva caught on the new pit tile is killed")


## Playtest regression: checking raw global_position instead of the
## GridMover's own committed_tile() let a larva already mid-step *toward*
## the tile finish walking onto a pit that opened moments into its step,
## since global_position mid-step is still interpolated mostly toward the
## FROM tile, not the actual in-flight destination.
func test_set_pit_at_kills_a_larva_mid_step_toward_the_new_pit_tile() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var target := tile + Vector2i.RIGHT
	level.dev_remove_wall_at(target)
	var mover := larva.get_node("GridMover") as GridMover
	assert_true(mover.try_step(Vector2i.RIGHT), "larva starts stepping toward the tile about to become a pit")
	mover.tick(0.03) # partway through -- still is_moving(), position still mostly in the FROM tile

	level.set_pit_at(target, true)

	assert_true(larva.is_queued_for_deletion(), "killed immediately even though its step animation hadn't landed yet")


func test_set_pit_at_leaves_a_larva_on_a_different_tile_alone() -> void:
	var level := _make_level()
	var larva := _first_larva(level)
	var tile := level.tile_of(larva.global_position)
	var elsewhere := tile + Vector2i(5, 5)
	level.dev_remove_wall_at(elsewhere)

	level.set_pit_at(elsewhere, true)

	assert_false(larva.is_queued_for_deletion(), "a pit elsewhere on the map doesn't touch an unrelated larva")
