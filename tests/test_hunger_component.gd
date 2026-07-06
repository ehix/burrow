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
