extends GutTest
## HatchlingsSkill (skill fixes bundle): each spawned TinySpiderling escorts
## around the same offset it was spawned at, so activation and the
## hatchling's own escort target agree without a second source of truth.

const HatchlingScene := preload("res://entities/skills/scenes/tiny_spiderling.tscn")


func _make_skill() -> HatchlingsSkill:
	var skill := HatchlingsSkill.new()
	skill.hatchling_scene = HatchlingScene
	skill.spawn_count = 1
	skill.spawn_radius = 24.0
	add_child_autofree(skill)
	# Every test in this file drives the cooldown by calling skill._process(delta)
	# directly with synthetic deltas. Leaving automatic per-frame processing on
	# would let the engine's own real-time _process() ticks sneak in during any
	# `await get_tree().process_frame` (needed elsewhere to let queue_free()'s
	# deferred tree_exited fire) and silently nibble at the cooldown by however
	# much wall-clock time actually elapsed — flaky and beside the point here.
	skill.set_process(false)
	return skill


func _make_caster() -> Node2D:
	var caster := Node2D.new()
	add_child_autofree(caster)
	caster.global_position = Vector2(400, 400)
	return caster


func test_on_activate_passes_the_spawn_offset_into_setup() -> void:
	var skill := _make_skill()
	var caster := _make_caster()

	skill._on_activate(caster)

	var hatchlings := get_tree().get_nodes_in_group("hatchlings")
	assert_eq(hatchlings.size(), 1)
	var hatchling: TinySpiderling = hatchlings[0]
	# _on_activate() parents the hatchling under get_tree().current_scene
	# (mirroring how the real HatchlingsSkill spawns it), not under this test
	# node, so add_child_autofree() on the skill/caster above never reaches
	# it — free it explicitly or it outlives the test and keeps ticking
	# against already-freed test doubles.
	autofree(hatchling)
	var expected_offset := Vector2(skill.spawn_radius, 0) # spawn_count=1, i=0 -> rotation 0
	assert_eq(hatchling.global_position, caster.global_position + expected_offset)

	caster.global_position += Vector2(100, 0)
	var before := hatchling.global_position.distance_to(caster.global_position + expected_offset)
	for i in 10:
		hatchling._physics_process(0.05)
	var after := hatchling.global_position.distance_to(caster.global_position + expected_offset)
	assert_lt(after, before, "the hatchling escorts toward the owner's new position at the same relative offset")


func test_cooldown_does_not_start_until_all_hatchlings_have_died() -> void:
	var skill := _make_skill()
	skill.cooldown = 5.0
	var caster := _make_caster()

	skill.activate(caster)
	# _on_activate() parents the spawned hatchling outside this test's node
	# (see test_on_activate_passes_the_spawn_offset_into_setup's comment
	# above), and this test never kills it, so free it explicitly here or it
	# leaks into later tests' "hatchlings" group queries.
	for hatchling in get_tree().get_nodes_in_group("hatchlings"):
		autofree(hatchling)

	assert_false(skill.can_activate(), "stays busy while the batch is alive")
	assert_eq(skill.remaining_cooldown(), 5.0, "shows the frozen cooldown value")

	skill._process(10.0) # well past `cooldown`, but nothing has died yet
	assert_false(skill.can_activate(), "still busy — nothing has died")


func test_cooldown_starts_once_the_last_hatchling_dies() -> void:
	var skill := _make_skill()
	skill.cooldown = 5.0
	var caster := _make_caster()
	skill.activate(caster)
	var hatchlings := get_tree().get_nodes_in_group("hatchlings")
	assert_eq(hatchlings.size(), 1)
	var hatchling: TinySpiderling = hatchlings[0]

	hatchling.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(skill.remaining_cooldown(), 5.0, "the real cooldown has just started")
	skill._process(5.0)
	assert_true(skill.can_activate(), "reactivatable once the real cooldown elapses")
