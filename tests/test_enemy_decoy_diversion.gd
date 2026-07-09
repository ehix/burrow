extends GutTest
## Decoy actually diverts enemy aggro now (design §3): Enemy._acquire_target()
## picks whichever of {the real player, any visible decoy} is nearer, so a
## closer decoy wins the CHASE contest even while the player is also visible
## — not just as a fallback once the player is hidden.

const EnemyScene := preload("res://entities/enemy/enemy.tscn")
const DecoyScene := preload("res://entities/skills/scenes/decoy.tscn")


func _make_enemy() -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(500, 500)
	return enemy


func _make_player(at: Vector2) -> Node2D:
	var player := Node2D.new()
	player.add_to_group("player")
	add_child_autofree(player)
	player.global_position = at
	return player


func _make_camouflaged_player(at: Vector2) -> Node2D:
	var player := _make_player(at)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var camo := CamouflageSkill.new()
	camo.name = "CamouflageSkill"
	player.add_child(camo)
	camo.activate(player)
	return player


func _make_decoy(at: Vector2) -> Decoy:
	var decoy: Decoy = DecoyScene.instantiate()
	add_child_autofree(decoy)
	decoy.setup(10.0)
	decoy.global_position = at
	return decoy


func test_targets_the_player_when_no_decoy_exists() -> void:
	var enemy := _make_enemy()
	var player := _make_player(enemy.global_position + Vector2(48, 0))
	enemy._player = player

	assert_eq(enemy._acquire_target(), player)


func test_a_closer_decoy_wins_over_a_farther_but_still_visible_player() -> void:
	var enemy := _make_enemy()
	var player := _make_player(enemy.global_position + Vector2(150, 0))
	var decoy := _make_decoy(enemy.global_position + Vector2(50, 0))
	enemy._player = player

	assert_eq(enemy._acquire_target(), decoy, "the nearer decoy diverts aggro")


func test_the_player_still_wins_over_a_farther_decoy() -> void:
	var enemy := _make_enemy()
	var player := _make_player(enemy.global_position + Vector2(50, 0))
	_make_decoy(enemy.global_position + Vector2(150, 0))
	enemy._player = player

	assert_eq(enemy._acquire_target(), player, "a decoy only diverts aggro when it's actually closer")


func test_a_camouflaged_player_is_still_diverted_to_a_visible_decoy() -> void:
	var enemy := _make_enemy()
	var player := _make_camouflaged_player(enemy.global_position + Vector2(50, 0))
	var decoy := _make_decoy(enemy.global_position + Vector2(150, 0))
	enemy._player = player

	assert_eq(enemy._acquire_target(), decoy,
		"camouflage hides the player, but a visible decoy still holds attention")


func test_returns_null_when_nothing_is_visible() -> void:
	var enemy := _make_enemy()
	var player := _make_camouflaged_player(enemy.global_position + Vector2(50, 0))
	enemy._player = player

	assert_null(enemy._acquire_target())


func test_update_state_enters_chase_targeting_the_nearer_decoy() -> void:
	var enemy := _make_enemy()
	var player := _make_player(enemy.global_position + Vector2(150, 0))
	var decoy := _make_decoy(enemy.global_position + Vector2(50, 0))
	enemy._player = player
	enemy.hunger.current_hunger = 0.0

	enemy._update_state()

	assert_eq(enemy.state, Enemy.State.CHASE)
	assert_eq(enemy._current_target, decoy)


func test_chase_melees_the_diverted_decoy_target() -> void:
	var enemy := _make_enemy()
	var decoy := _make_decoy(enemy.global_position + Vector2(20, 0)) # within melee_range
	enemy._player = _make_player(enemy.global_position + Vector2(900, 900)) # far away, irrelevant
	enemy._current_target = decoy
	enemy.state = Enemy.State.CHASE

	var hurtbox := decoy.get_node("Hurtbox") as Hurtbox
	var health_before := hurtbox.health.current_health
	enemy._do_chase()

	assert_lt(hurtbox.health.current_health, health_before,
		"the enemy's melee lands on the decoy it's chasing")


func test_fight_back_always_targets_the_real_player_not_a_diverted_decoy() -> void:
	var enemy := _make_enemy()
	var player := _make_player(enemy.global_position + Vector2(20, 0)) # in melee range
	var decoy := _make_decoy(enemy.global_position + Vector2(900, 900)) # far, irrelevant
	enemy._player = player
	enemy._current_target = decoy # as if CHASE had been diverted here

	var hurtbox := decoy.get_node("Hurtbox") as Hurtbox
	var health_before := hurtbox.health.current_health
	enemy._fight_back()

	assert_eq(hurtbox.health.current_health, health_before,
		"fight_back reacts to the real threat, never a harmless diverted decoy")
