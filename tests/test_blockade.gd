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


func test_at_tile_finds_a_blockade_on_the_given_tile() -> void:
	var blockade := _make_blockade()
	blockade.global_position = Vector2(240, 240) # tile (5,5)
	assert_eq(Blockade.at_tile(get_tree(), Vector2i(5, 5), 48), blockade)


func test_at_tile_returns_null_for_an_empty_tile() -> void:
	var blockade := _make_blockade()
	blockade.global_position = Vector2(240, 240) # tile (5,5)
	assert_null(Blockade.at_tile(get_tree(), Vector2i(9, 9), 48))


func test_destroy_frees_the_blockade_regardless_of_hit_count() -> void:
	var blockade := _make_blockade()
	blockade.setup(6) # would normally take 6 hits — destroy() bypasses that entirely
	blockade.destroy()
	assert_true(blockade.is_queued_for_deletion())
