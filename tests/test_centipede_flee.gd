extends GutTest
## Centipede's combat-provoked flee, end-to-end (sub-project H, design §5):
## found via whole-branch review -- _nearest_boundary_tile() originally
## targeted a literal boundary-ring tile (Level.is_boundary()'s outermost
## ring), which MazeGenerator always leaves solid and _tunnel_toward()
## deliberately refuses to ever carve (same guardrail RemoveWallsSkill/
## SeismicCompaction honor) -- so the flee target was permanently
## unreachable, and a fleeing Centipede never arrived, never despawned, and
## carved fresh interior walls forever on every retry tick. Every other
## crawl test drives _crawl_step() with a hand-set state/target/path that
## never exercises _begin_flee()'s own target computation, so this gap went
## uncaught until a real end-to-end flee was driven to completion. These
## tests pump _crawl_step() directly in a loop (never the real
## crawl_step_time SceneTreeTimer), mirroring every other test in this
## file's own convention.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	# This file places its own centipede(s) at tiles it controls directly --
	# free any centipede Level.build() auto-seeded (Task 8) so it can never
	# collide with (or be found instead of) the tiles these tests place.
	for node in get_tree().get_nodes_in_group("centipedes"):
		node.free()
	return level


func _make_centipede(level: Level, tiles: Array[Vector2i]) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at(tiles)
	return centipede


func test_nearest_boundary_tile_is_always_open_and_touches_the_boundary() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])

	var target: Vector2i = centipede._nearest_boundary_tile()

	assert_true(level.maze.is_open(target.x, target.y), "the flee target is always reachable open floor")
	assert_false(level.is_boundary(target), "the flee target is never the unreachable solid boundary ring itself")
	var touches_boundary := false
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if level.is_boundary(target + dir):
			touches_boundary = true
			break
	assert_true(touches_boundary, "the flee target is adjacent to the boundary ring -- a real edge-of-the-maze tile")


func test_a_full_flee_eventually_despawns_the_centipede() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])
	centipede.hits_to_flee = 1

	centipede.take_hit() # crosses the threshold -- _begin_flee() computes a real target

	assert_eq(centipede.state, Centipede.State.FLEEING)
	var ticks := 0
	while is_instance_valid(centipede) and not centipede.is_queued_for_deletion() and ticks < 200:
		centipede._crawl_step()
		ticks += 1

	assert_true(centipede.is_queued_for_deletion(),
		"a real flee, driven to completion, actually reaches its target and despawns")


func test_a_full_flee_never_carves_more_than_a_handful_of_walls() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var centipede := _make_centipede(level, [cells[0]])
	centipede.hits_to_flee = 1
	var open_before := level.maze.open_cells().size()

	centipede.take_hit()
	var ticks := 0
	while is_instance_valid(centipede) and not centipede.is_queued_for_deletion() and ticks < 200:
		centipede._crawl_step()
		ticks += 1

	var carved := level.maze.open_cells().size() - open_before
	assert_true(centipede.is_queued_for_deletion(), "sanity: the flee actually completed")
	assert_lt(carved, 10, "a flee to an already-open, boundary-adjacent target needs little to no tunneling")
