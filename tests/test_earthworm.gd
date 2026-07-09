extends GutTest
## Earthworm (design §6): a durable, inedible obstacle that blocks a corridor
## like a wall until melee'd enough times, then burrows toward the nearest
## map-boundary side and despawns there.

const EarthwormScene := preload("res://entities/earthworm/earthworm.tscn")


func _make_worm() -> Earthworm:
	var worm: Earthworm = EarthwormScene.instantiate()
	add_child_autofree(worm)
	return worm


func test_joins_the_earthworms_group() -> void:
	var worm := _make_worm()
	assert_true(worm.is_in_group("earthworms"))


func test_is_on_the_world_collision_layer_so_it_blocks_like_a_wall() -> void:
	var worm := _make_worm()
	assert_eq(worm.collision_layer, 1)


func test_take_hit_below_threshold_stays_blocking() -> void:
	var worm := _make_worm()
	worm.hits_to_flee = 4
	worm.take_hit()
	worm.take_hit()
	worm.take_hit()
	assert_eq(worm.state, Earthworm.State.BLOCKING)


func test_take_hit_at_threshold_begins_retreating() -> void:
	var worm := _make_worm()
	worm.hits_to_flee = 4
	for i in 4:
		worm.take_hit()
	assert_eq(worm.state, Earthworm.State.RETREATING)


func test_further_hits_while_retreating_are_a_noop() -> void:
	var worm := _make_worm()
	worm.hits_to_flee = 2
	worm.take_hit()
	worm.take_hit() # now retreating
	worm.take_hit() # must not error or re-trigger anything
	assert_eq(worm.state, Earthworm.State.RETREATING)


func test_retreating_worm_moves_and_eventually_despawns() -> void:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()

	var worm := _make_worm()
	worm.bind_level(level)
	worm.global_position = Vector2(20, 20) # very close to the top-left edge
	worm.retreat_speed = 1000.0 # fast, so the test doesn't need many ticks
	worm.hits_to_flee = 1
	worm.take_hit() # begins retreating

	for i in 20:
		worm._physics_process(0.05)

	assert_true(worm.is_queued_for_deletion(), "reaches the boundary and despawns")
