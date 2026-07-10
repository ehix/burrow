extends GutTest
## Unit tests for HungerComponent (design §9: "growth, HP drain at max,
## satiate, overflow emission").


func _make_health(max_health: float = 100.0) -> HealthComponent:
	var h := HealthComponent.new()
	h.max_health = max_health
	h.current_health = max_health
	autofree(h)
	return h


func _make_hunger(health: HealthComponent) -> HungerComponent:
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.hunger_rate = 10.0
	hunger.starvation_damage_rate = 5.0
	hunger.current_hunger = 0.0
	hunger.health = health
	autofree(hunger)
	return hunger


func test_hunger_grows_over_time() -> void:
	var hunger := _make_hunger(_make_health())
	hunger.tick(1.0)
	assert_almost_eq(hunger.current_hunger, 10.0, 0.001)


func test_hunger_clamps_at_max() -> void:
	var hunger := _make_hunger(_make_health())
	hunger.tick(100.0)
	assert_eq(hunger.current_hunger, 100.0)
	assert_true(hunger.is_starving())


func test_starvation_drains_health() -> void:
	var health := _make_health(100.0)
	var hunger := _make_hunger(health)
	hunger.current_hunger = 100.0 # already starving
	watch_signals(hunger)
	hunger.tick(2.0) # 2s * 5 hp/s = 10 damage
	assert_almost_eq(health.current_health, 90.0, 0.001)
	assert_signal_emitted(hunger, "became_starving")


func test_no_starvation_damage_when_fed() -> void:
	var health := _make_health(100.0)
	var hunger := _make_hunger(health)
	hunger.current_hunger = 50.0
	hunger.tick(1.0)
	assert_eq(health.current_health, 100.0)


func test_satiate_reduces_hunger() -> void:
	var hunger := _make_hunger(_make_health())
	hunger.current_hunger = 60.0
	var overflow := hunger.satiate(40.0)
	assert_eq(hunger.current_hunger, 20.0)
	assert_eq(overflow, 0.0)


func test_satiate_overflow_past_full() -> void:
	var hunger := _make_hunger(_make_health())
	hunger.current_hunger = 30.0
	watch_signals(hunger)
	var overflow := hunger.satiate(50.0) # only 30 needed; 20 overflows
	assert_eq(hunger.current_hunger, 0.0)
	assert_eq(overflow, 20.0)
	assert_signal_emitted_with_parameters(hunger, "overflowed", [20.0])


func test_satiate_overflow_heals_the_sibling_health() -> void:
	var health := _make_health(100.0)
	health.current_health = 60.0 # damaged, so the heal is visible
	var hunger := _make_hunger(health)
	hunger.excess_heal_ratio = 0.5
	hunger.current_hunger = 30.0
	hunger.satiate(50.0) # only 30 needed; 20 overflows -> heals 20 * 0.5 = 10
	assert_almost_eq(health.current_health, 70.0, 0.001, "overflow heals at excess_heal_ratio")


func test_satiate_without_overflow_does_not_heal() -> void:
	var health := _make_health(100.0)
	health.current_health = 60.0
	var hunger := _make_hunger(health)
	hunger.excess_heal_ratio = 0.5
	hunger.current_hunger = 60.0
	hunger.satiate(40.0) # no overflow: exactly enough to reach zero hunger
	assert_almost_eq(health.current_health, 60.0, 0.001, "no overflow, no heal")


func test_satiate_overflow_heal_clamps_at_max_health() -> void:
	var health := _make_health(100.0) # already full
	var hunger := _make_hunger(health)
	hunger.excess_heal_ratio = 0.5
	hunger.current_hunger = 30.0
	hunger.satiate(50.0) # 20 overflow, would heal 10, but already at max
	assert_almost_eq(health.current_health, 100.0, 0.001, "heal clamps at max health")


func test_zero_excess_heal_ratio_disables_the_heal() -> void:
	var health := _make_health(100.0)
	health.current_health = 60.0
	var hunger := _make_hunger(health)
	hunger.excess_heal_ratio = 0.0
	hunger.current_hunger = 30.0
	hunger.satiate(50.0) # 20 overflow, but the ratio is disabled
	assert_almost_eq(health.current_health, 60.0, 0.001, "a zero ratio disables the heal entirely")


func test_add_raises_hunger_clamped_to_max() -> void:
	var hunger := _make_hunger(_make_health())
	hunger.current_hunger = 90.0
	hunger.add(5.0)
	assert_eq(hunger.current_hunger, 95.0, "add raises hunger")
	hunger.add(20.0)
	assert_eq(hunger.current_hunger, 100.0, "clamped at max")


func test_charge_all_taxes_every_spider() -> void:
	# Two spiders in the tree; charge_all should raise both their hungers.
	var a := Node2D.new()
	a.add_to_group("spiders")
	var ha := HungerComponent.new()
	ha.current_hunger = 10.0
	a.add_child(ha)
	add_child_autofree(a)
	var b := Node2D.new()
	b.add_to_group("spiders")
	var hb := HungerComponent.new()
	hb.current_hunger = 20.0
	b.add_child(hb)
	add_child_autofree(b)
	HungerComponent.charge_all(get_tree(), 4.0)
	assert_eq(ha.current_hunger, 14.0, "first spider taxed")
	assert_eq(hb.current_hunger, 24.0, "second spider taxed")


func test_god_mode_freezes_hunger_for_the_player() -> void:
	var owner := Node2D.new()
	owner.add_to_group("player")
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.hunger_rate = 10.0
	hunger.current_hunger = 50.0
	owner.add_child(hunger)
	add_child_autofree(owner)
	GameState.god_mode = true
	hunger.tick(5.0) # would otherwise add 50 hunger
	hunger.add(20.0) # metabolic action cost also frozen
	GameState.god_mode = false # don't leak into other tests
	assert_eq(hunger.current_hunger, 50.0, "god mode freezes the player's hunger")


func test_freeze_enemy_freezes_hunger_for_the_enemy() -> void:
	var owner := Node2D.new()
	owner.add_to_group("enemy")
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.hunger_rate = 10.0
	hunger.current_hunger = 50.0
	owner.add_child(hunger)
	add_child_autofree(owner)
	GameState.freeze_enemy = true
	hunger.tick(5.0) # would otherwise add 50 hunger
	hunger.add(20.0) # metabolic action cost also frozen
	GameState.freeze_enemy = false # don't leak into other tests
	assert_eq(hunger.current_hunger, 50.0, "playtest mode freezes the enemy's hunger")


func test_freeze_enemy_does_not_affect_the_player() -> void:
	var owner := Node2D.new()
	owner.add_to_group("player")
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.hunger_rate = 10.0
	hunger.current_hunger = 50.0
	owner.add_child(hunger)
	add_child_autofree(owner)
	GameState.freeze_enemy = true
	hunger.tick(5.0)
	GameState.freeze_enemy = false
	assert_eq(hunger.current_hunger, 100.0, "freeze_enemy is scoped to the enemy, not the player")


func test_charge_all_exempts_a_frozen_enemy() -> void:
	var enemy := Node2D.new()
	enemy.add_to_group("spiders")
	enemy.add_to_group("enemy")
	var hunger := HungerComponent.new()
	hunger.current_hunger = 10.0
	enemy.add_child(hunger)
	add_child_autofree(enemy)
	GameState.freeze_enemy = true
	HungerComponent.charge_all(get_tree(), 4.0)
	GameState.freeze_enemy = false # don't leak into other tests
	assert_eq(hunger.current_hunger, 10.0, "a frozen enemy is exempt from the metabolic tax")


func test_charge_all_starvation_fail_safe_exempts_a_frozen_enemy() -> void:
	# The starving fail-safe drains health directly, bypassing add()'s own
	# guard, so it needs its own check in the charge_all loop.
	var enemy := Node2D.new()
	enemy.add_to_group("spiders")
	enemy.add_to_group("enemy")
	var health := HealthComponent.new()
	health.max_health = 100.0
	health.current_health = 100.0
	enemy.add_child(health)
	var hunger := HungerComponent.new()
	hunger.current_hunger = hunger.max_hunger # already starving
	enemy.add_child(hunger)
	add_child_autofree(enemy)
	GameState.freeze_enemy = true
	HungerComponent.charge_all(get_tree(), 6.0)
	GameState.freeze_enemy = false # don't leak into other tests
	assert_eq(health.current_health, 100.0, "a frozen enemy takes no starvation-fail-safe damage either")


func test_charge_all_drains_health_instead_once_starving() -> void:
	# A spider already at max hunger has nowhere for the charge to go, so the
	# fail-safe drains its health instead (actions never go free while starving).
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	var health := HealthComponent.new()
	health.max_health = 100.0
	health.current_health = 100.0
	spider.add_child(health)
	var hunger := HungerComponent.new()
	hunger.current_hunger = hunger.max_hunger # already starving
	spider.add_child(hunger)
	add_child_autofree(spider)
	HungerComponent.charge_all(get_tree(), 6.0)
	assert_eq(hunger.current_hunger, hunger.max_hunger, "hunger stays capped, does not overflow")
	assert_almost_eq(health.current_health, 94.0, 0.001, "the charge drained health instead")
