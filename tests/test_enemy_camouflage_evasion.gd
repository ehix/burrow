extends GutTest
## Camouflage's actual payoff (design §3): a camouflaged player is invisible
## to Enemy._can_see_player() regardless of range/line-of-sight, so CHASE
## can't start against a hidden player, and an active CHASE drops away the
## moment camouflage goes up.

const EnemyScene := preload("res://entities/enemy/enemy.tscn")


func _make_enemy() -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(500, 500)
	return enemy


func _make_player_with_camouflage() -> Node2D:
	var player := Node2D.new()
	player.add_to_group("player")
	add_child_autofree(player)
	# CamouflageSkill._on_activate() needs a "Sprite" child to dim — without
	# one it no-ops (never sets `active`), same as it would for a real
	# spider missing a Sprite, so the double must have one too.
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var camo := CamouflageSkill.new()
	# A runtime-created node isn't auto-named after its class_name (that only
	# happens for nodes placed in a .tscn) — Enemy._player_is_camouflaged()
	# looks it up as "CamouflageSkill" by name, exactly like player.tscn wires
	# it, so the test double must match that name too.
	camo.name = "CamouflageSkill"
	player.add_child(camo)
	return player


func test_cannot_see_a_camouflaged_player_even_at_point_blank_range() -> void:
	var enemy := _make_enemy()
	var player := _make_player_with_camouflage()
	player.global_position = enemy.global_position
	enemy._player = player
	(player.get_node("CamouflageSkill") as CamouflageSkill).activate(player)

	assert_false(enemy._can_see_player(), "camouflage hides the player even up close")


func test_uncamouflaged_player_is_seen_normally() -> void:
	var enemy := _make_enemy()
	var player := _make_player_with_camouflage() # has the skill, but never activated
	player.global_position = enemy.global_position
	enemy._player = player

	assert_true(enemy._can_see_player())


func test_camouflage_drops_an_enemy_out_of_an_active_chase() -> void:
	var enemy := _make_enemy()
	var player := _make_player_with_camouflage()
	player.global_position = enemy.global_position + Vector2(48, 0)
	enemy._player = player
	enemy.state = Enemy.State.CHASE
	enemy._state_lock_left = 0.0
	enemy.hunger.current_hunger = 0.0 # so the fallback branch lands on PATROL, not SEEK_FOOD

	(player.get_node("CamouflageSkill") as CamouflageSkill).activate(player)
	enemy._update_state()

	assert_ne(enemy.state, Enemy.State.CHASE, "an active chase ends once the target vanishes")
