extends GutTest
## Blockade (design §3): a destructible physical obstacle — higher durability
## than a web trap, frees itself once hit enough times, and sits on the world
## collision layer so it blocks spiders via their existing test_move checks
## with zero changes to Player/Enemy's own collision masks.

const BlockadeScene := preload("res://entities/skills/scenes/blockade.tscn")


func _make_blockade() -> Blockade:
	var blockade: Blockade = BlockadeScene.instantiate()
	add_child_autofree(blockade)
	return blockade


func test_survives_hits_under_its_threshold() -> void:
	var blockade := _make_blockade()
	blockade.setup(3)
	blockade.take_hit()
	blockade.take_hit()
	assert_false(blockade.is_queued_for_deletion())


func test_destroyed_on_the_nth_hit() -> void:
	var blockade := _make_blockade()
	blockade.setup(3)
	blockade.take_hit()
	blockade.take_hit()
	blockade.take_hit()
	assert_true(blockade.is_queued_for_deletion())


func test_is_on_the_world_collision_layer_so_it_blocks_like_a_wall() -> void:
	var blockade := _make_blockade()
	assert_eq(blockade.collision_layer, 1)
