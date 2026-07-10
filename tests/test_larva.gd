extends GutTest
## A web-killed larva leaves the larvae group so nobody can eat it.
## Instantiates the larva *scene* (not Larva.new()) so its GridMover child
## exists — otherwise @onready $GridMover is null and _physics_process errors.

const LarvaScene := preload("res://entities/larva/larva.tscn")
const WebTrapScene := preload("res://entities/web/web_trap.tscn")


func _make_larva() -> Larva:
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)
	return larva


func test_web_kill_removes_from_larvae_group() -> void:
	var larva := _make_larva()
	assert_true(larva.is_in_group("larvae"), "spawns in the larvae group")
	larva.web_kill()
	assert_false(larva.is_in_group("larvae"), "web-killed larva is no longer edible")


func test_web_kill_is_idempotent() -> void:
	var larva := _make_larva()
	larva.web_kill()
	larva.web_kill() # must not error on an already-killed larva
	assert_false(larva.is_in_group("larvae"))


func test_step_finished_bumps_when_near_a_spider() -> void:
	var larva := _make_larva()
	larva.global_position = Vector2(500, 500)
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	spider.global_position = Vector2(505, 500) # well within the bump radius
	add_child_autofree(spider)
	var sprite := larva.get_node("Sprite") as Node2D
	var rest := sprite.position
	larva._on_step_finished()
	assert_ne(sprite.position, rest, "the larva's sprite is nudged when a spider is close")


func test_step_finished_no_bump_when_no_spider_nearby() -> void:
	var larva := _make_larva()
	larva.global_position = Vector2(500, 500)
	var sprite := larva.get_node("Sprite") as Node2D
	var rest := sprite.position
	larva._on_step_finished()
	assert_eq(sprite.position, rest, "no bump without a nearby spider")


func test_step_finished_bumps_anywhere_on_the_same_tile_not_just_within_12px() -> void:
	# Regression: the check used to be a 12px radius, which a spider well
	# inside the same 48px tile (e.g. 20px away) could fall outside of. It's
	# now an exact tile comparison, so anywhere on the tile counts.
	var larva := _make_larva()
	larva.global_position = Vector2(500, 500)
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	spider.global_position = Vector2(520, 500) # same tile, but 20px away
	add_child_autofree(spider)
	var sprite := larva.get_node("Sprite") as Node2D
	var rest := sprite.position
	larva._on_step_finished()
	assert_ne(sprite.position, rest, "bump fires anywhere on the shared tile")


func test_set_caught_stops_a_mid_flight_step_from_dragging_it_off_centre() -> void:
	var larva := _make_larva()
	larva.global_position = Vector2(500, 500)
	larva._mover.try_step(Vector2i.RIGHT)
	larva._mover.tick(0.05) # partway through the 0.34s step
	larva.set_caught(Vector2(700, 700)) # a trap snaps it to its centre mid-step
	larva._mover.tick(0.1) # further frames must not drag it back off that position
	assert_eq(larva.global_position, Vector2(700, 700),
		"a caught larva must not drift off the trap centre")


## An occupied web is a boundary for other larvae, like a dead end — an empty
## web isn't (larvae otherwise pass through webs freely).
func test_wander_never_steps_onto_a_tile_with_a_caught_larva() -> void:
	var larva := _make_larva()
	larva.global_position = Vector2(264, 264) # tile (5,5)
	larva._last_dir = Vector2i.RIGHT

	var trap: WebTrap = WebTrapScene.instantiate()
	add_child_autofree(trap)
	trap.global_position = Vector2(312, 264) # tile (6,5), directly RIGHT of the larva
	trap.catch_larva(_make_larva()) # occupy it

	larva._wander_step()
	assert_ne(larva._last_dir, Vector2i.RIGHT, "never steps onto the occupied web's tile")


func test_wander_is_unaffected_by_an_empty_web() -> void:
	var larva := _make_larva()
	larva.global_position = Vector2(264, 264) # tile (5,5)
	assert_false(larva._is_occupied_web(Vector2i(6, 5)), "no trap there at all — not a boundary")


func test_step_time_scales_with_growth_at_baseline() -> void:
	var larva := _make_larva()
	larva.growth.size_scale = 1.0
	larva._wander_step()
	assert_almost_eq(larva._mover.step_time, larva._base_step_time, 0.001)


func test_step_time_scales_with_growth_at_a_midpoint() -> void:
	var larva := _make_larva()
	larva.growth.size_scale = 1.75
	larva._wander_step()
	assert_almost_eq(larva._mover.step_time, larva._base_step_time * 1.75, 0.001)


func test_step_time_scales_with_growth_at_the_cap() -> void:
	var larva := _make_larva()
	larva.growth.size_scale = 2.5
	larva._wander_step()
	assert_almost_eq(larva._mover.step_time, larva._base_step_time * 2.5, 0.001)


func test_nudge_toward_also_applies_growth_speed() -> void:
	var larva := _make_larva()
	larva.growth.size_scale = 2.0
	larva.nudge_toward(larva.global_position + Vector2(100, 0))
	assert_almost_eq(larva._mover.step_time, larva._base_step_time * 2.0, 0.001)
