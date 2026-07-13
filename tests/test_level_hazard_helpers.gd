extends GutTest
## Level's new hazard/plane-support helpers (design §1 and §7): is_boundary,
## is_blocked across both planes, patch_pit_at, and collapse_tile_at as the
## exact inverse of dev_remove_wall_at.


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_is_boundary_matches_maze_data() -> void:
	var level := _make_level()
	assert_true(level.is_boundary(Vector2i(0, 0)))
	assert_false(level.is_boundary(Vector2i(1, 1)))


func test_is_blocked_ground_respects_pits() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	assert_false(level.is_blocked(open_cell, Level.Layer.GROUND))
	level.maze.set_pit(open_cell.x, open_cell.y, true)
	assert_true(level.is_blocked(open_cell, Level.Layer.GROUND))


func test_is_blocked_ceiling_ignores_pits() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.maze.set_pit(open_cell.x, open_cell.y, true)
	assert_false(level.is_blocked(open_cell, Level.Layer.CEILING),
		"the ceiling passes over a pit that blocks the ground")


func test_patch_pit_at_clears_the_flag() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.maze.set_pit(open_cell.x, open_cell.y, true)
	level.patch_pit_at(open_cell)
	assert_false(level.maze.is_pit(open_cell.x, open_cell.y))


func test_collapse_tile_at_is_inverse_of_dev_remove_wall_at() -> void:
	var level := _make_level()
	var removed := level.dev_remove_wall_at(Vector2i(0, 0))
	assert_true(removed)
	assert_true(level.maze.is_open(0, 0))

	# collapse_tile_at itself refuses a boundary tile (guardrail), so exercise
	# the round trip on a known-interior cell centre instead (odd/odd tiles
	# are always carved open — see test_cell_centres_are_open).
	var interior_cell := Vector2i(3, 3)
	assert_true(level.maze.is_open(interior_cell.x, interior_cell.y))
	assert_true(level.collapse_tile_at(interior_cell))
	assert_false(level.maze.is_open(interior_cell.x, interior_cell.y))
	assert_true(level._astar.is_point_solid(interior_cell))


func test_collapse_tile_at_refuses_the_boundary() -> void:
	var level := _make_level()
	assert_false(level.collapse_tile_at(Vector2i(0, 0)), "boundary tiles can never be collapsed")


func test_collapse_tile_at_on_an_already_wall_tile_is_a_noop() -> void:
	var level := _make_level()
	var wall_cell := Vector2i(2, 2) # even/even — always a wall in the expanded grid
	assert_false(level.maze.is_open(wall_cell.x, wall_cell.y))
	assert_false(level.collapse_tile_at(wall_cell))


func test_set_water_at_blocks_ground_movement_like_a_pit() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_water_at(open_cell, true)
	assert_true(level.maze.is_pit(open_cell.x, open_cell.y))
	assert_true(level.is_blocked(open_cell, Level.Layer.GROUND))


func test_set_water_at_spawns_a_distinct_blue_marker_not_the_pit_marker() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_water_at(open_cell, true)
	assert_true(level._water_nodes.has(open_cell))
	assert_false(level._pit_nodes.has(open_cell), "water uses its own marker, not the brown pit one")
	var marker: Node2D = level._water_nodes[open_cell]
	assert_eq((marker as Polygon2D).color, Level.WATER_MARKER_COLOR)


func test_set_water_at_false_clears_the_block_and_frees_the_marker() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_water_at(open_cell, true)
	level.set_water_at(open_cell, false)
	assert_false(level.maze.is_pit(open_cell.x, open_cell.y))
	assert_false(level._water_nodes.has(open_cell))


func test_set_water_at_true_destroys_a_web_trap_on_that_tile() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	var trap := WebTrap.new()
	level.add_child(trap)
	trap.global_position = level._tile_centre(open_cell.x, open_cell.y)

	level.set_water_at(open_cell, true)

	assert_true(trap.spent, "flooding a tile destroys the web trap on it")


func test_set_water_at_true_submerges_an_item_on_that_tile() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	var pickup: WorldItemPickup = preload("res://entities/items/world_item_pickup.tscn").instantiate()
	level.add_child(pickup)
	pickup.global_position = level._tile_centre(open_cell.x, open_cell.y)

	level.set_water_at(open_cell, true)

	assert_false(pickup.visible, "flooding a tile submerges the item on it")
	assert_false(pickup.monitoring)


func test_set_water_at_false_resurfaces_an_item_on_that_tile() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	var pickup: WorldItemPickup = preload("res://entities/items/world_item_pickup.tscn").instantiate()
	level.add_child(pickup)
	pickup.global_position = level._tile_centre(open_cell.x, open_cell.y)
	level.set_water_at(open_cell, true)

	level.set_water_at(open_cell, false)

	assert_true(pickup.visible, "draining a tile resurfaces the item on it")
	assert_true(pickup.monitoring)


func test_patch_pit_at_on_a_flooded_tile_clears_water_state_too() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_water_at(open_cell, true)

	level.patch_pit_at(open_cell)

	assert_false(level.maze.is_pit(open_cell.x, open_cell.y))
	assert_false(level._water_nodes.has(open_cell), "patching a flooded tile also clears its blue marker")


func test_collapse_tile_at_destroys_a_larva_on_the_tile() -> void:
	var level := _make_level()
	var interior_cell := Vector2i(3, 3)
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	level.add_child(larva)
	larva.global_position = level._tile_centre(interior_cell.x, interior_cell.y)

	level.collapse_tile_at(interior_cell)

	assert_true(larva.is_queued_for_deletion(), "a larva on a collapsed tile is destroyed")


func test_collapse_tile_at_destroys_a_web_trap_on_the_tile() -> void:
	var level := _make_level()
	var interior_cell := Vector2i(3, 3)
	var trap := WebTrap.new()
	level.add_child(trap)
	trap.global_position = level._tile_centre(interior_cell.x, interior_cell.y)

	level.collapse_tile_at(interior_cell)

	assert_true(trap.spent, "a web trap on a collapsed tile is destroyed")


func test_collapse_tile_at_destroys_an_item_on_the_tile_permanently() -> void:
	var level := _make_level()
	var interior_cell := Vector2i(3, 3)
	var pickup: WorldItemPickup = preload("res://entities/items/world_item_pickup.tscn").instantiate()
	level.add_child(pickup)
	pickup.global_position = level._tile_centre(interior_cell.x, interior_cell.y)

	level.collapse_tile_at(interior_cell)

	assert_true(pickup.is_queued_for_deletion(),
		"unlike water (which submerges then restores), compaction destroys an item outright")


func test_draining_a_flood_over_a_natural_pit_leaves_the_pit_blocking() -> void:
	var level := _make_level()
	var open_cell: Vector2i = level.maze.open_cells()[0]
	level.set_pit_at(open_cell, true)

	level.set_water_at(open_cell, true)
	level.set_water_at(open_cell, false)

	assert_true(level.maze.is_pit(open_cell.x, open_cell.y),
		"the natural pit under the flood must still block after the water drains")
	assert_true(level.is_blocked(open_cell, Level.Layer.GROUND))
	assert_true(level._pit_nodes.has(open_cell), "the brown pit marker survives untouched")
	assert_false(level._water_nodes.has(open_cell), "the blue water marker was cleared")


func test_collapse_tile_at_clears_water_state_on_a_flooded_tile() -> void:
	var level := _make_level()
	var interior_cell := Vector2i(3, 3)
	level.set_water_at(interior_cell, true)

	level.collapse_tile_at(interior_cell)

	assert_false(level._water_nodes.has(interior_cell), "no dangling water marker on the new wall")
	assert_false(level._water_tiles.has(interior_cell), "no dangling water tracking on the new wall")
	assert_false(level.maze.is_open(interior_cell.x, interior_cell.y), "the tile really did become a wall")
