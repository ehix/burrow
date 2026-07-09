extends GutTest
## Regression guard: the player and enemy spider must never end up on the same
## tile, even under worst-case contention (both stepping toward each other
## every single frame). Their collision masks already hard-block one another
## (player mask includes the enemy layer and vice versa); this locks that in.

const PlayerScene := preload("res://entities/player/player.tscn")
const EnemyScene := preload("res://entities/enemy/enemy.tscn")


func test_adjacent_spiders_never_overlap_under_contention() -> void:
	var player: CharacterBody2D = PlayerScene.instantiate()
	var enemy: CharacterBody2D = EnemyScene.instantiate()
	add_child_autofree(player)
	add_child_autofree(enemy)
	player.global_position = Vector2(500, 500)
	enemy.global_position = Vector2(548, 500) # one tile to the right, adjacent
	# Let the physics server register both bodies before querying test_move —
	# without this, the broadphase hasn't seen the new shapes yet and blocking
	# checks would pass trivially (a test artifact, not a real-game condition).
	await get_tree().process_frame
	await get_tree().process_frame

	var p_mover := player.get_node("GridMover")
	var e_mover := enemy.get_node("GridMover")
	var dt := 1.0 / 60.0

	for i in range(300):
		p_mover.try_step(Vector2i.RIGHT)
		e_mover.try_step(Vector2i.LEFT)
		p_mover.tick(dt)
		e_mover.tick(dt)
		var dist := player.global_position.distance_to(enemy.global_position)
		assert_gt(dist, 40.0, "spiders must not overlap (frame %d, dist %.1f)" % [i, dist])


## Regression for the real bug reported from a playthrough: an enemy mid-step
## toward an empty tile, then a knockback lands the player on that same tile
## before the enemy's step finishes. Must be refused.
func test_knockback_is_refused_into_a_tile_the_enemy_is_mid_step_toward() -> void:
	var player: CharacterBody2D = PlayerScene.instantiate()
	var enemy: CharacterBody2D = EnemyScene.instantiate()
	add_child_autofree(player)
	add_child_autofree(enemy)
	player.global_position = Vector2(264, 264) # tile (5,5)
	enemy.global_position = Vector2(360, 264)  # tile (7,5)
	await get_tree().process_frame
	await get_tree().process_frame

	var e_mover := enemy.get_node("GridMover")
	assert_true(e_mover.try_step(Vector2i.LEFT), "enemy starts toward the empty tile (6,5)")
	e_mover.tick(1.0 / 60.0) # partway through the step, not yet landed

	var p_mover := player.get_node("GridMover")
	assert_false(p_mover.knockback(Vector2i.RIGHT),
		"must not land the player on the tile the enemy already committed to")
	assert_ne(player.global_position, Vector2(312, 264),
		"player did not end up on the contested tile (6,5)")
