extends GutTest
## World._cycle_class() (dev tool Q): advances GameState.selected_class
## through all four classes, wrapping, and re-applies it to the live player.

const WorldScene := preload("res://world/world.tscn")


func _make_world() -> Node:
	var world = WorldScene.instantiate()
	add_child_autofree(world)
	return world


func before_each() -> void:
	GameState.selected_class = SpiderClassData.SpiderClass.WOLF


func after_each() -> void:
	GameState.selected_class = SpiderClassData.SpiderClass.WOLF


func test_cycle_class_advances_and_wraps() -> void:
	var world := _make_world()
	world._cycle_class()
	assert_eq(GameState.selected_class, SpiderClassData.SpiderClass.WEAVER)
	world._cycle_class()
	assert_eq(GameState.selected_class, SpiderClassData.SpiderClass.DECOY)
	world._cycle_class()
	assert_eq(GameState.selected_class, SpiderClassData.SpiderClass.NET_CASTER, "wraps 3 -> 0")
	world._cycle_class()
	assert_eq(GameState.selected_class, SpiderClassData.SpiderClass.WOLF)


func test_cycle_class_re_applies_to_the_live_player() -> void:
	var world := _make_world()
	var player := world._current_player() as Player
	world._cycle_class()
	assert_eq(player._active_class, GameState.selected_class)
