extends GutTest
## Level.is_blocked() must report a live Blockade's tile as blocked on BOTH
## planes (playtest fix: ceiling blocking previously never consulted
## physical colliders at all, so a spider on the ceiling could freely pass
## over a Blockade underneath it).

const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_a_blockade_blocks_ground() -> void:
	var level := _make_level()
	var player := level.player as Player
	var tile := level.tile_of(player.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)
	var blockade: Blockade = BlockadeScene.instantiate()
	add_child_autofree(blockade)
	blockade.global_position = level.centre_of(ahead)

	assert_true(level.is_blocked(ahead, Level.Layer.GROUND))


func test_a_blockade_blocks_the_ceiling_too() -> void:
	var level := _make_level()
	var player := level.player as Player
	var tile := level.tile_of(player.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)
	var blockade: Blockade = BlockadeScene.instantiate()
	add_child_autofree(blockade)
	blockade.global_position = level.centre_of(ahead)

	assert_true(level.is_blocked(ahead, Level.Layer.CEILING),
		"a blockade blocks the ceiling plane too — it can't be crawled over")


func test_no_blockade_leaves_the_ceiling_unaffected() -> void:
	var level := _make_level()
	var player := level.player as Player
	var tile := level.tile_of(player.global_position)
	var ahead := tile + Vector2i(1, 0)
	level.maze.set_open(ahead.x, ahead.y)

	assert_false(level.is_blocked(ahead, Level.Layer.CEILING), "no blockade there — ceiling is unaffected")
