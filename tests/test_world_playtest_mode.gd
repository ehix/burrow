extends GutTest
## World._toggle_playtest_mode() (dev tool 0): drives freeze_enemy and
## god_mode together from GameState.playtest_mode, and restores both to false
## on toggle-off regardless of any independent J/G toggling in between.

const WorldScene := preload("res://world/world.tscn")


func _make_world() -> Node:
	var world = WorldScene.instantiate()
	add_child_autofree(world)
	return world


func after_each() -> void:
	GameState.playtest_mode = false
	GameState.freeze_enemy = false
	GameState.freeze_others = false
	GameState.god_mode = false


func test_toggle_on_sets_freeze_enemy_and_god_mode() -> void:
	var world := _make_world()
	world._toggle_playtest_mode()
	assert_true(GameState.playtest_mode)
	assert_true(GameState.freeze_enemy)
	assert_true(GameState.god_mode)


func test_toggle_off_clears_freeze_enemy_and_god_mode() -> void:
	var world := _make_world()
	world._toggle_playtest_mode() # on
	world._toggle_playtest_mode() # off
	assert_false(GameState.playtest_mode)
	assert_false(GameState.freeze_enemy)
	assert_false(GameState.god_mode)


func test_toggle_off_clears_flags_even_if_independently_toggled_in_between() -> void:
	var world := _make_world()
	world._toggle_playtest_mode() # on: freeze_enemy = god_mode = true
	GameState.god_mode = false # hand-tuned mid-session via the G key
	world._toggle_playtest_mode() # off: forces both back to false regardless
	assert_false(GameState.freeze_enemy)
	assert_false(GameState.god_mode)


func test_playtest_mode_leaves_freeze_others_untouched() -> void:
	# Larvae/hazards must stay live under Playtest Mode (only the enemy is
	# demobilized), so the broader freeze_others flag is never touched here.
	var world := _make_world()
	world._toggle_playtest_mode()
	assert_false(GameState.freeze_others)
