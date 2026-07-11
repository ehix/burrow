extends GutTest
## MineSpiderling (skill fixes bundle): Egg Mine's cosmetic burst flourish —
## appears, waits briefly, deals one tiny damage tick to whatever's still
## nearby, then frees. No movement, no chase, no persistent AI.

const MineSpiderlingScene := preload("res://entities/skills/scenes/mine_spiderling.tscn")


func _make_spiderling() -> MineSpiderling:
	var spiderling: MineSpiderling = MineSpiderlingScene.instantiate()
	add_child_autofree(spiderling)
	return spiderling


func _make_target(group: String, at: Vector2) -> Node2D:
	var target := Node2D.new()
	target.add_to_group(group)
	add_child_autofree(target)
	target.global_position = at
	var health := HealthComponent.new()
	health.current_health = health.max_health
	autofree(health)
	var hurtbox := Hurtbox.new()
	hurtbox.health = health
	hurtbox.name = "Hurtbox"
	target.add_child(hurtbox)
	return target


func test_joins_the_mine_spiderlings_group() -> void:
	var spiderling := _make_spiderling()
	assert_true(spiderling.is_in_group("mine_spiderlings"))


func test_does_not_explode_before_explode_after_elapses() -> void:
	var spiderling := _make_spiderling()
	spiderling.explode_after = 1.0

	spiderling._physics_process(0.6)

	assert_false(spiderling.is_queued_for_deletion())


func test_explodes_and_deals_damage_to_a_nearby_target_after_explode_after() -> void:
	var spiderling := _make_spiderling()
	spiderling.explode_after = 0.3
	spiderling.damage = 1.0
	spiderling.damage_radius = 24.0
	var target := _make_target("spiders", spiderling.global_position + Vector2(5, 0))

	spiderling._physics_process(0.35)

	var hurtbox := target.get_node("Hurtbox") as Hurtbox
	assert_lt(hurtbox.health.current_health, hurtbox.health.max_health)
	assert_true(spiderling.is_queued_for_deletion())


func test_ignores_a_target_outside_damage_radius() -> void:
	var spiderling := _make_spiderling()
	spiderling.explode_after = 0.1
	spiderling.damage_radius = 24.0
	var target := _make_target("spiders", spiderling.global_position + Vector2(500, 0))

	spiderling._physics_process(0.2)

	var hurtbox := target.get_node("Hurtbox") as Hurtbox
	assert_eq(hurtbox.health.current_health, hurtbox.health.max_health)
