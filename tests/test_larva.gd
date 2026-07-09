extends GutTest
## A web-killed larva leaves the larvae group so nobody can eat it.
## Instantiates the larva *scene* (not Larva.new()) so its GridMover child
## exists — otherwise @onready $GridMover is null and _physics_process errors.

const LarvaScene := preload("res://entities/larva/larva.tscn")


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
