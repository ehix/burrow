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
