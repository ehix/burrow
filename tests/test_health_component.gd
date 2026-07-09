extends GutTest
## Unit tests for HealthComponent (design §9: "damage, clamping, death signal").


func _make(max_health: float = 100.0) -> HealthComponent:
	var h := HealthComponent.new()
	h.max_health = max_health
	h.current_health = max_health
	autofree(h)
	return h


func test_take_damage_reduces_health() -> void:
	var h := _make(100.0)
	h.take_damage(30.0)
	assert_eq(h.current_health, 70.0)


func test_damage_clamps_at_zero() -> void:
	var h := _make(100.0)
	h.take_damage(1000.0)
	assert_eq(h.current_health, 0.0)
	assert_true(h.is_dead())


func test_died_emits_once_at_zero() -> void:
	var h := _make(50.0)
	watch_signals(h)
	h.take_damage(50.0)
	h.take_damage(10.0) # already dead; must not fire again
	assert_signal_emit_count(h, "died", 1)


func test_heal_clamps_at_max() -> void:
	var h := _make(100.0)
	h.take_damage(40.0)
	h.heal(1000.0)
	assert_eq(h.current_health, 100.0)


func test_dead_cannot_heal() -> void:
	var h := _make(100.0)
	h.take_damage(100.0)
	h.heal(50.0)
	assert_eq(h.current_health, 0.0)


func test_health_changed_carries_values() -> void:
	var h := _make(100.0)
	watch_signals(h)
	h.take_damage(25.0)
	assert_signal_emitted_with_parameters(h, "health_changed", [75.0, 100.0])


func test_god_mode_blocks_damage_for_the_player() -> void:
	var owner := Node2D.new()
	owner.add_to_group("player")
	var h := HealthComponent.new()
	h.max_health = 100.0
	h.current_health = 100.0
	owner.add_child(h)
	add_child_autofree(owner)
	GameState.god_mode = true
	h.take_damage(50.0)
	GameState.god_mode = false # don't leak into other tests
	assert_eq(h.current_health, 100.0, "god mode blocks damage to the player")


func test_god_mode_does_not_protect_a_non_player_spider() -> void:
	var owner := Node2D.new()
	owner.add_to_group("spiders") # e.g. the enemy: not the "player" group
	var h := HealthComponent.new()
	h.max_health = 100.0
	h.current_health = 100.0
	owner.add_child(h)
	add_child_autofree(owner)
	GameState.god_mode = true
	h.take_damage(50.0)
	GameState.god_mode = false
	assert_eq(h.current_health, 50.0, "god mode is scoped to the player only")
