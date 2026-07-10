extends GutTest
## A web shot routes its effect by what it strikes. Drives the collision
## callbacks directly (no physics frames). Vars are typed WebShot/Larva so the
## subclass methods resolve at parse time (an inferred Node would skip the file).

const WebShotScene := preload("res://entities/web/web_shot.tscn")
const LarvaScene := preload("res://entities/larva/larva.tscn")


func _make_shot() -> WebShot:
	var shot: WebShot = WebShotScene.instantiate()
	add_child_autofree(shot)
	return shot


func _make_larva() -> Larva:
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)
	return larva


func test_reduced_damage_default() -> void:
	assert_almost_eq(_make_shot().damage, 8.0, 0.001, "web damage lowered from 20 to 8")


func test_launch_default_speed_mult_leaves_velocity_unchanged() -> void:
	var shot := _make_shot()
	shot.launch(Vector2.RIGHT, null)
	assert_almost_eq(shot._velocity.length(), shot.speed, 0.001)


func test_launch_scales_velocity_by_speed_mult() -> void:
	var shot := _make_shot()
	shot.launch(Vector2.RIGHT, null, 1.4)
	assert_almost_eq(shot._velocity.length(), shot.speed * 1.4, 0.001)


func test_hitting_a_larva_web_kills_it() -> void:
	var shot := _make_shot()
	var larva := _make_larva()
	assert_true(larva.is_in_group("larvae"))
	shot._on_body_entered(larva)
	assert_false(larva.is_in_group("larvae"), "a web-killed larva is no longer edible")


func test_hitting_a_trap_registers_a_web_hit() -> void:
	var shot := _make_shot()
	var trap := WebTrap.new()
	add_child_autofree(trap)
	shot._on_body_entered(trap)
	assert_eq(trap.web_hits, 1, "the shot lands one destructive hit on the trap")


func test_hitting_a_blockade_registers_a_hit() -> void:
	# Each shot is spent after resolving one hit, so a "third hit destroys it"
	# check needs three separate shots — mirrors three real projectiles landing.
	var blockade := Blockade.new()
	add_child_autofree(blockade)
	blockade.setup(3)
	_make_shot()._on_body_entered(blockade)
	assert_false(blockade.is_queued_for_deletion(), "one hit shouldn't destroy a 3-hit blockade")
	_make_shot()._on_body_entered(blockade)
	_make_shot()._on_body_entered(blockade)
	assert_true(blockade.is_queued_for_deletion(), "the third hit destroys it")
