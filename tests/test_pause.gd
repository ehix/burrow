extends GutTest
## Pause toggle: freezes the tree and shows/hides the HUD's "PAUSED" label.
## World is PROCESS_MODE_ALWAYS so it keeps receiving the toggle while paused.

const WorldScene := preload("res://world/world.tscn")
const HudScene := preload("res://ui/hud.tscn")


func after_each() -> void:
	get_tree().paused = false # never leak a paused tree into later tests


func test_hud_set_paused_visible_toggles_the_label() -> void:
	var hud: Node = HudScene.instantiate()
	add_child_autofree(hud)
	assert_false(hud.paused_label.visible)
	hud.set_paused_visible(true)
	assert_true(hud.paused_label.visible)
	hud.set_paused_visible(false)
	assert_false(hud.paused_label.visible)


func test_toggle_pause_pauses_the_tree_and_shows_the_label() -> void:
	var world := WorldScene.instantiate()
	add_child_autofree(world)
	await get_tree().process_frame

	assert_false(get_tree().paused)
	world._toggle_pause()
	assert_true(get_tree().paused)
	assert_true(world.hud.paused_label.visible)

	world._toggle_pause()
	assert_false(get_tree().paused)
	assert_false(world.hud.paused_label.visible)


## Regression: pausing must actually stop gameplay. World is ALWAYS (so its
## own input keeps working while paused) and process_mode is inherited down
## the tree, so Level needs its own explicit PAUSABLE override — otherwise it
## silently inherits ALWAYS from World and pausing freezes nothing at all.
func test_level_is_pausable_even_though_world_is_always() -> void:
	var world := WorldScene.instantiate()
	add_child_autofree(world)
	await get_tree().process_frame

	assert_eq(world.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(world._level.process_mode, Node.PROCESS_MODE_PAUSABLE,
		"Level must not inherit World's ALWAYS mode, or pause would do nothing")
