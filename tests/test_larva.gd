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
