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
