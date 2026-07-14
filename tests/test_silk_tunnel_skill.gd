extends GutTest
## SilkTunnelSkill (skill fixes bundle): lays web across tile_count tiles
## ahead of the caster — bumped from 4 to 6 per playtest feedback.

const TrapScene := preload("res://entities/web/web_trap.tscn")


func after_each() -> void:
	# _lay_tunnel() parents each trap under whatever _spawn_parent() resolves
	# to (the GUT runner root in headless tests, since there's no real
	# current_scene) — not under the per-test `level`, so it isn't cleaned up
	# by add_child_autofree(level). Free traps here so one test's tunnel
	# doesn't leak into the next test's group counts.
	for node in get_tree().get_nodes_in_group("traps"):
		node.queue_free()
	if get_tree().get_nodes_in_group("traps").size() > 0:
		await get_tree().process_frame


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_skill() -> SilkTunnelSkill:
	var skill := SilkTunnelSkill.new()
	skill.trap_scene = TrapScene
	add_child_autofree(skill)
	return skill


func test_default_tile_count_is_6() -> void:
	var skill := _make_skill()
	assert_eq(skill.tile_count, 6)


func test_lays_the_tunnel_from_the_tile_a_mid_step_caster_is_committed_to() -> void:
	# Same bug BlockadeSkill._target_tile() was fixed for (see its own doc
	# comment): computing the starting tile from the caster's raw,
	# interpolated global_position instead of GridMover.committed_tile()
	# meant that for roughly the first half of an in-flight step, the
	# starting tile resolved to the tile the caster was *leaving*, not the
	# one they're now committed to -- spamming this while moving could lay
	# the tunnel starting from a tile inconsistent with where the caster
	# visually was, reading as a web placed "between tiles" (playtest bug).
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	var mover := player.get_node_or_null("GridMover") as GridMover
	mover.set_process(false) # drive the step manually, no competing auto-tick this frame
	mover.block_check = func(_dir: Vector2i) -> bool: return false # force the step to begin regardless of physical/logical wall state -- isolates this test to starting-tile computation
	var start_tile := level.tile_of(player.global_position)
	player.facing = Vector2.RIGHT # away from the maze's top-left spawn corner -- keeps all tiles below non-negative
	for offset in [1, 2]:
		var tile := start_tile + Vector2i(offset, 0)
		level.maze.set_open(tile.x, tile.y) # guaranteed open -- avoids flaking if the maze ever puts a wall there
		level.set_pit_at(tile, false)
	mover.try_step(Vector2i.RIGHT) # begin stepping toward start_tile + (1, 0); still mid-flight, position unmoved

	skill._on_activate(player)

	var traps := level.get_tree().get_nodes_in_group("traps")
	assert_gt(traps.size(), 0, "at least one trap was placed")
	var first_trap := traps[0] as WebTrap
	assert_eq(level.tile_of(first_trap.global_position), start_tile + Vector2i(2, 0),
		"the tunnel starts from the tile the caster is committed to (start_tile+1), not the one they're leaving -- so the first trap in the line lands one further out")
