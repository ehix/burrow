extends GutTest
## Centipede's boxed-in tunnel fallback (sub-project H, design §6): when no
## open+dry path exists to the target, it carves the single best adjacent
## wall tile and retries -- the "escape-through-tunnels... unless blocked
## in" case from the roadmap's original phrasing.

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


## Only floods neighbors that are actually open floor -- Level.set_water_at()
## records _water_tiles unconditionally (it does not itself guard on
## is_open() the way MazeData.set_pit() does), so calling it on a wall tile
## would leave that tile permanently flagged "flooded" even after
## _tunnel_toward() later carves it open, which is not what "sealing in" is
## meant to simulate. A still-solid wall neighbor already blocks on its own
## and needs no flood flag.
func _seal_in(level: Level, tile: Vector2i) -> void:
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor: Vector2i = tile + dir
		if level.maze.is_open(neighbor.x, neighbor.y):
			level.set_water_at(neighbor, true)


## A true cell-centre (odd/odd tile -- see MazeData's own doc comment on the
## "expanded" grid representation) guaranteed to have at least one adjacent
## non-boundary wall tile. The fixed cells[0] (this maze's top-left corner)
## has only two possible non-boundary neighbors, and at LOOP_CHANCE=0.7 both
## are frequently already carved open, leaving _tunnel_toward() nothing to
## carve through no matter how correctly it's implemented -- searching for a
## cell with a real wall neighbor fixes that. Restricting the search to
## cell-centres (skipping already-open connector tiles) matters too: a
## connector tile's only "wall" neighbor is an even/even corner tile whose
## OTHER three neighbors are independent, unrelated maze edges -- carving it
## open is frequently a dead end. A cell-centre's non-boundary neighbors are
## always the direct connector to another cell-centre, so carving one always
## reaches real, already-connected territory.
func _find_boxable_cell(level: Level) -> Vector2i:
	for cell in level.maze.open_cells():
		if cell.x % 2 == 0 or cell.y % 2 == 0:
			continue
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor: Vector2i = cell + dir
			if not level.maze.is_boundary(neighbor.x, neighbor.y) and not level.maze.is_open(neighbor.x, neighbor.y):
				return cell
	return level.maze.open_cells()[0]


func test_tunnel_toward_carves_exactly_one_wall_tile_when_boxed_in() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = _find_boxable_cell(level)
	_seal_in(level, start)
	var centipede := _make_centipede(level, [start])
	var open_before := level.maze.open_cells().size()

	var carved: bool = centipede._tunnel_toward(cells[cells.size() - 1])

	assert_true(carved)
	assert_eq(level.maze.open_cells().size(), open_before + 1, "exactly one new tile was carved open")


func test_tunnel_toward_never_carves_a_boundary_tile() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = _find_boxable_cell(level)
	_seal_in(level, start)
	var centipede := _make_centipede(level, [start])
	var before: Dictionary = {}
	for cell in level.maze.open_cells():
		before[cell] = true

	centipede._tunnel_toward(cells[cells.size() - 1])

	for cell in level.maze.open_cells():
		if not before.has(cell):
			assert_false(level.is_boundary(cell), "the newly carved tile is never on the boundary")


## _start_crawl()'s own doc comment is explicit that a single call isn't
## guaranteed to succeed: carving opens exactly one wall per call (see
## _tunnel_toward()), and the newly-reachable pocket can itself still be
## fully sealed off from `target`, needing another carve next tick.
## _crawl_step()'s real production retry loop (a fresh _start_crawl() call
## every crawl_step_time) is what actually guarantees eventual escape, not
## a single call -- so this test drives that same retry loop directly
## (never the real timer -- mirrors every other test in this file) up to a
## generous bound rather than asserting success after just one call.
func test_start_crawl_finds_a_path_after_tunneling_through_when_boxed_in() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = _find_boxable_cell(level)
	_seal_in(level, start)
	var centipede := _make_centipede(level, [start])
	centipede._target = cells[cells.size() - 1]

	var tries := 0
	while centipede._path.is_empty() and tries < 10:
		centipede._start_crawl()
		tries += 1

	assert_false(centipede._path.is_empty(),
		"boxed-in start_crawl tunnels through (over one or more retries) and finds a path")


## Playtest follow-up: _start_crawl() now tries reversing the body (leading
## with the tail instead) before ever tunneling -- see
## test_centipede_reverse.gd. Confirms the fallback chain still reaches
## tunneling when reversing genuinely can't help either: a 2-segment body
## with EVERY open neighbor on BOTH ends flooded (not just the tail's own
## side, the way a self-filled dead-end blocks only one direction) has no
## valid path forward or reversed, so this must still end up carving
## exactly like it did before the reversal fallback existed.
func test_start_crawl_still_falls_through_to_tunneling_when_both_ends_of_a_multi_segment_body_are_sealed() -> void:
	var level := _make_level()
	var cells := level.maze.open_cells()
	var start: Vector2i = _find_boxable_cell(level)
	var second := Vector2i.ZERO
	var found_second := false
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var candidate: Vector2i = start + dir
		if level.maze.is_open(candidate.x, candidate.y):
			second = candidate
			found_second = true
			break
	assert_true(found_second, "sanity: the maze must have at least one open neighbor here")
	# Seal every open neighbor of both ends, excluding each other (flooding
	# either body tile itself would spuriously trigger notify_flooded()
	# before this test ever calls _start_crawl() itself).
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = start + dir
		if n != second and level.maze.is_open(n.x, n.y):
			level.set_water_at(n, true)
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n: Vector2i = second + dir
		if n != start and level.maze.is_open(n.x, n.y):
			level.set_water_at(n, true)
	var centipede := _make_centipede(level, [start, second])
	centipede._target = cells[cells.size() - 1]

	var tries := 0
	while centipede._path.is_empty() and tries < 10:
		centipede._start_crawl()
		tries += 1

	assert_false(centipede._path.is_empty(),
		"both ends genuinely sealed -- reversing can't help, but tunneling (over one or more retries) still finds a path")
