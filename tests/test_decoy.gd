extends GutTest
## Decoy (design §3): reuses HealthComponent/Hurtbox so existing attack code
## (Player._melee's "spiders" loop, WebShot's generic Hurtbox check) already
## resolves against it with zero special-casing; frees on death or once its
## lifetime elapses, whichever comes first.

const DecoyScene := preload("res://entities/skills/scenes/decoy.tscn")


func _make_decoy() -> Decoy:
	var decoy: Decoy = DecoyScene.instantiate()
	add_child_autofree(decoy)
	return decoy


func test_joins_the_spiders_and_decoys_groups() -> void:
	var decoy := _make_decoy()
	assert_true(decoy.is_in_group("spiders"), "so existing spider-targeting code already finds it")
	assert_true(decoy.is_in_group("decoys"), "so real combat logic can tell it apart from a threat")


func test_dies_like_a_real_spider_when_its_health_reaches_zero() -> void:
	var decoy := _make_decoy()
	decoy.setup(30.0)
	var hurtbox := decoy.get_node("Hurtbox") as Hurtbox
	hurtbox.receive_hit(100.0, null)
	assert_true(decoy.is_queued_for_deletion())


func test_expires_after_its_lifetime_even_undamaged() -> void:
	var decoy := _make_decoy()
	decoy.setup(1.0)
	decoy._physics_process(0.6)
	assert_false(decoy.is_queued_for_deletion())
	decoy._physics_process(0.5)
	assert_true(decoy.is_queued_for_deletion())


func test_apply_web_hit_is_a_harmless_noop() -> void:
	var decoy := _make_decoy()
	decoy.apply_web_hit(Vector2i.RIGHT, 0.5, 1.0, 1.0) # must not error
	assert_true(true, "reached this point without erroring")
