extends GutTest
## Larva.heal_value() (design §2) delegates to its LarvaGrowth child, and both
## WebTrap.try_consume() and Enemy._eat_larva() use it in preference to their
## own flat satiation constants; the sprite visibly scales with growth too.

const LarvaScene := preload("res://entities/larva/larva.tscn")
const EnemyScene := preload("res://entities/enemy/enemy.tscn")


func _make_larva() -> Larva:
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)
	return larva


func test_fresh_larva_heal_value_matches_the_base_default() -> void:
	var larva := _make_larva()
	assert_almost_eq(larva.heal_value(), LarvaGrowth.BASE_HEAL_VALUE, 0.001)


func test_heal_value_grows_as_the_larva_ages() -> void:
	var larva := _make_larva()
	larva.growth.tick(30.0)
	assert_gt(larva.heal_value(), LarvaGrowth.BASE_HEAL_VALUE)


func test_sprite_scale_follows_growth_size_scale() -> void:
	var larva := _make_larva()
	larva.growth.size_scale = 1.5
	larva._physics_process(0.0)
	assert_almost_eq(larva._sprite.scale.x, larva._base_sprite_scale.x * 1.5, 0.001)


func test_web_trap_consume_uses_the_larvas_own_heal_value() -> void:
	var trap := WebTrap.new()
	add_child_autofree(trap)
	var larva := _make_larva()
	larva.growth.size_scale = 2.0 # heals more than the trap's own flat satiation default
	trap.catch_larva(larva)

	var spider := Node2D.new()
	add_child_autofree(spider)
	var health := HealthComponent.new()
	health.current_health = health.max_health
	autofree(health)
	var hunger := HungerComponent.new()
	hunger.health = health
	hunger.current_hunger = 100.0
	spider.add_child(hunger)

	trap.try_consume(spider)

	var expected_heal := LarvaGrowth.BASE_HEAL_VALUE + LarvaGrowth.HEAL_PER_SIZE * 1.0
	assert_almost_eq(hunger.current_hunger, 100.0 - expected_heal, 0.001)


func test_enemy_eat_larva_uses_growth_scaled_heal_value() -> void:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.hunger.current_hunger = 100.0
	var larva := _make_larva()
	larva.growth.size_scale = 2.0

	enemy._eat_larva(larva)

	var expected_heal := LarvaGrowth.BASE_HEAL_VALUE + LarvaGrowth.HEAL_PER_SIZE * 1.0
	assert_almost_eq(enemy.hunger.current_hunger, 100.0 - expected_heal, 0.001)


func test_web_trap_falls_back_to_flat_satiation_for_a_bare_test_double() -> void:
	var trap := WebTrap.new()
	add_child_autofree(trap)
	var bare_larva := Node2D.new() # no heal_value() method at all
	bare_larva.add_to_group("larvae")
	autofree(bare_larva)
	trap.catch_larva(bare_larva)

	var spider := Node2D.new()
	add_child_autofree(spider)
	var health := HealthComponent.new()
	health.current_health = health.max_health
	autofree(health)
	var hunger := HungerComponent.new()
	hunger.health = health
	hunger.current_hunger = 100.0
	spider.add_child(hunger)

	trap.try_consume(spider)

	assert_almost_eq(hunger.current_hunger, 100.0 - trap.satiation, 0.001)
