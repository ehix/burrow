extends GutTest
## RemoveWallsSkill (playtest fix): destroys a Blockade on its target tile
## outright instead of attempting to carve a wall there — a Blockade always
## sits on an already-open floor tile, so wall-carving would find nothing to
## remove. With no Blockade in the way, existing wall-carving behavior is
## unchanged.

const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func _make_skill() -> RemoveWallsSkill:
	var skill := RemoveWallsSkill.new()
	add_child_autofree(skill)
	return skill


func test_destroys_a_blockade_on_the_target_tile() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target := level.tile_of(player.global_position) + Vector2i(1, 0)
	var blockade: Blockade = BlockadeScene.instantiate()
	add_child_autofree(blockade)
	blockade.global_position = level.centre_of(target)

	skill._on_activate(player)

	assert_true(blockade.is_queued_for_deletion(), "the blockade is destroyed outright")


func test_carves_a_wall_as_before_when_no_blockade_is_in_the_way() -> void:
	var level := _make_level()
	var player := level.player as Player
	var skill := _make_skill()
	player.facing = Vector2.RIGHT
	var target := level.tile_of(player.global_position) + Vector2i(1, 0)
	level.maze.set_wall(target.x, target.y)

	skill._on_activate(player)

	assert_true(level.maze.is_open(target.x, target.y), "the wall is carved open as before")
