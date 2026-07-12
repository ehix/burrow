extends GutTest
## Player's generic two-button skill input (Hatchlings/VFX/input round):
## skill_1/skill_2 resolve positionally through CLASS_SKILLS for whichever
## class is active, instead of each skill owning its own dedicated action.
## Driven through _skill_for_slot() directly rather than real Input events —
## Input.is_action_just_pressed() only clears on a real engine frame
## boundary, which synchronous test calls never cross (see
## test_control_indicators.gd's own note on this).

const PlayerScene := preload("res://entities/player/player.tscn")


func _make_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func test_skill_slot_0_resolves_to_the_current_classs_first_skill() -> void:
	var player := _make_player() # defaults to Wolf -> hatchlings, egg_mine
	assert_eq(player._skill_for_slot(0), player._hatchlings)
	assert_eq(player._skill_for_slot(1), player._egg_mine)


func test_skill_slots_update_after_switching_class() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.DECOY)
	assert_eq(player._skill_for_slot(0), player._camouflage)
	assert_eq(player._skill_for_slot(1), player._decoy)


func test_skill_slot_0_resolves_to_net_hold_for_net_caster() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_eq(player._skill_for_slot(0), player._net_hold)
	assert_eq(player._skill_for_slot(1), player._net_shot)


func test_out_of_range_slot_returns_null() -> void:
	var player := _make_player()
	assert_null(player._skill_for_slot(2))
	assert_null(player._skill_for_slot(-1))
