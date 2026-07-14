extends GutTest
## Centipede's flood-provoked relocate (sub-project H, design §5): distinct
## from a combat-provoked flee -- it picks a fresh dry spot and resumes
## BLOCKING there instead of despawning at the boundary.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	# This file places its own centipede(s) at tiles it controls directly --
	# free any centipede Level.build() auto-seeded (Task 8) so it can never
	# collide with (or be found instead of) the tiles these tests place, and
	# so it can't react to this file's own flooding (Task 7's
	# notify_flooded()) with a side-effecting tunnel-carve (Task 6).
	for node in get_tree().get_nodes_in_group("centipedes"):
		node.free()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


func test_notify_flooded_transitions_to_relocating() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])

	centipede.notify_flooded()

	assert_eq(centipede.state, Centipede.State.RELOCATING)


func test_notify_flooded_is_a_noop_while_already_fleeing() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])
	centipede.state = Centipede.State.FLEEING

	centipede.notify_flooded()

	assert_eq(centipede.state, Centipede.State.FLEEING, "already fleeing takes priority")


func test_pick_relocate_target_never_picks_a_flooded_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])
	for cell in cells:
		if cell != start:
			level.set_water_at(cell, true)

	var target: Vector2i = centipede._pick_relocate_target()

	assert_eq(target, start, "every other open tile is flooded -- nowhere valid, so it stays put")


func test_level_set_water_at_notifies_an_occupying_centipede() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = cells[0]
	var centipede := _make_centipede(level, [start])

	level.set_water_at(start, true)

	assert_eq(centipede.state, Centipede.State.RELOCATING, "flooding the tile it occupies triggers a relocate")
