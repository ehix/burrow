extends GutTest
## A web-killed larva leaves the larvae group so nobody can eat it.


func test_web_kill_removes_from_larvae_group() -> void:
	var larva := Larva.new()
	add_child_autofree(larva)
	assert_true(larva.is_in_group("larvae"), "spawns in the larvae group")
	larva.web_kill()
	assert_false(larva.is_in_group("larvae"), "web-killed larva is no longer edible")


func test_web_kill_is_idempotent() -> void:
	var larva := Larva.new()
	add_child_autofree(larva)
	larva.web_kill()
	larva.web_kill() # must not error on an already-killed larva
	assert_false(larva.is_in_group("larvae"))
