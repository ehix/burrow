extends GutTest
## BlockadeSkill (playtest fix): places ahead of the caster, not at their own
## tile (the bug that trapped the caster inside their own barricade);
## refuses to activate at all if the enemy spider occupies the target tile;
## crushes a larva standing there instead.

const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")


func after_each() -> void:
	# activate()/_on_activate() parent a placed blockade under whatever
	# _spawn_parent() resolves to (the GUT runner root in headless tests,
	# since there's no real current_scene) — not under the per-test `level`,
	# so it isn't cleaned up by add_child_autofree(level). Free it here so a
	# blockade placed in one test doesn't leak into the next test's group
	# counts.
	for node in get_tree().get_nodes_in_group("blockades"):
		node.queue_free()
	if get_tree().get_nodes_in_group("blockades").size() > 0:
		await get_tree().process_frame


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


class FakeSpider:
	extends CharacterBody2D
	var facing := Vector2.RIGHT


func _make_skill() -> BlockadeSkill:
	var skill := BlockadeSkill.new()
	skill.blockade_scene = BlockadeScene
	add_child_autofree(skill)
	return skill


func test_places_the_blockade_ahead_of_the_caster_not_at_their_own_tile() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	var start_tile := level.tile_of(player.global_position)
	player.facing = Vector2.RIGHT

	skill._on_activate(player)

	var blockade := level.get_tree().get_first_node_in_group("blockades") as Blockade
	assert_not_null(blockade, "a blockade was placed")
	assert_eq(level.tile_of(blockade.global_position), start_tile + Vector2i(1, 0),
		"placed one tile ahead of the caster, not on top of them")
	assert_ne(level.tile_of(blockade.global_position), start_tile,
		"never placed on the caster's own tile — that's the bug being fixed")


func test_places_beyond_the_tile_a_mid_step_caster_is_stepping_into_not_on_it() -> void:
	# Playtest bug: computing the target tile from the caster's raw,
	# interpolated global_position (instead of GridMover.committed_tile())
	# meant that for roughly the first half of an in-flight step, the target
	# tile resolved to the very tile the caster was stepping into — spawning
	# a solid blockade right where the caster was about to arrive.
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	var mover := player.get_node_or_null("GridMover") as GridMover
	mover.set_process(false) # drive the step manually, no competing auto-tick this frame
	mover.block_check = func(_dir: Vector2i) -> bool: return false # force the step to begin regardless of physical/logical wall state — isolates this test to target-tile computation
	var start_tile := level.tile_of(player.global_position)
	player.facing = Vector2.RIGHT # away from the maze's top-left spawn corner — keeps all tiles below non-negative (Level.tile_of() truncates rather than floors, so a negative tile would round-trip incorrectly here regardless of this fix)
	mover.try_step(Vector2i.RIGHT) # begin stepping toward start_tile + (1, 0); still mid-flight, position unmoved

	skill._on_activate(player)

	var blockade := level.get_tree().get_first_node_in_group("blockades") as Blockade
	assert_not_null(blockade, "a blockade was placed")
	assert_eq(level.tile_of(blockade.global_position), start_tile + Vector2i(2, 0),
		"placed beyond the tile the caster is stepping into (committed_tile() + facing), not on the tile the caster is about to occupy")


func test_activate_refuses_when_the_enemy_spider_occupies_the_target_tile() -> void:
	var level := _make_level()
	var player := level.player as Player
	var enemy := level.get_tree().get_first_node_in_group("enemy") as Node2D
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target_tile := level.tile_of(player.global_position) + Vector2i(1, 0)
	enemy.global_position = level.centre_of(target_tile)

	var fired := skill.activate(player)

	assert_false(fired, "can't place a blockade on top of the enemy spider")
	assert_eq(level.get_tree().get_nodes_in_group("blockades").size(), 0, "nothing was placed")


func test_activate_refuses_when_the_target_tile_is_already_wall_blocked() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target_tile := level.tile_of(player.global_position) + Vector2i(1, 0)
	level.maze.set_wall(target_tile.x, target_tile.y)

	var fired := skill.activate(player)

	assert_false(fired, "can't place a blockade into a wall")
	assert_eq(level.get_tree().get_nodes_in_group("blockades").size(), 0, "nothing was placed")


func test_activate_refuses_when_a_blockade_already_occupies_the_target_tile() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target_tile := level.tile_of(player.global_position) + Vector2i(1, 0)
	var existing: Blockade = BlockadeScene.instantiate()
	add_child_autofree(existing)
	existing.global_position = level.centre_of(target_tile)

	var fired := skill.activate(player)

	assert_false(fired, "can't stack a second blockade onto an existing one")
	assert_eq(level.get_tree().get_nodes_in_group("blockades").size(), 1,
		"only the pre-existing blockade remains — nothing new was added")


func test_activate_succeeds_when_the_target_tile_is_clear() -> void:
	var level := _make_level()
	var player := level.player as Player
	var enemy := level.get_tree().get_first_node_in_group("enemy") as Node2D
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	enemy.global_position = player.global_position + Vector2(1000, 1000) # guaranteed far away — avoids flaking if the maze ever spawns it adjacent
	var target_tile := level.tile_of(player.global_position) + Vector2i(1, 0)
	level.maze.set_open(target_tile.x, target_tile.y) # guaranteed open — avoids flaking if the maze ever puts a wall there
	level.set_pit_at(target_tile, false) # set_open() alone doesn't clear a pre-existing natural pit flag

	var fired := skill.activate(player)

	assert_true(fired)
	assert_eq(level.get_tree().get_nodes_in_group("blockades").size(), 1)


func test_crushes_a_larva_standing_on_the_target_tile() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target_tile := level.tile_of(player.global_position) + Vector2i(1, 0)
	var larva := level.get_tree().get_first_node_in_group("larvae") as Larva
	larva.global_position = level.centre_of(target_tile)
	assert_true(larva.is_in_group("larvae"))

	skill._on_activate(player)

	assert_false(larva.is_in_group("larvae"), "the larva under the blockade was crushed and killed")
	assert_eq(level.get_tree().get_nodes_in_group("blockades").size(), 1, "the blockade is still placed")


func test_a_larva_elsewhere_is_untouched() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var larva := level.get_tree().get_first_node_in_group("larvae") as Larva
	larva.global_position = player.global_position + Vector2(500, 500) # far away

	skill._on_activate(player)

	assert_true(larva.is_in_group("larvae"), "a larva far from the target tile is unaffected")
