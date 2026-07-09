extends GutTest
## Enemy relays its own health/hunger changes to EventBus, same as Player —
## needed so the HUD can show live enemy stats (a fresh enemy is instanced
## each depth, so the HUD can't just cache a single reference).

const EnemyScene := preload("res://entities/enemy/enemy.tscn")


func test_enemy_primes_health_and_hunger_on_ready() -> void:
	var enemy: Enemy = EnemyScene.instantiate()
	watch_signals(EventBus)
	add_child_autofree(enemy)
	assert_signal_emitted_with_parameters(EventBus, "health_changed",
		[enemy, enemy.health.current_health, enemy.health.max_health])
	assert_signal_emitted_with_parameters(EventBus, "hunger_changed",
		[enemy, enemy.hunger.current_hunger, enemy.hunger.max_hunger])


func test_enemy_relays_damage_to_event_bus() -> void:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	watch_signals(EventBus)
	enemy.health.take_damage(10.0)
	var expected := enemy.health.current_health
	assert_signal_emitted_with_parameters(EventBus, "health_changed", [enemy, expected, enemy.health.max_health])


## Regression: _eat_larva used to hardcode the emitted overflow to 0.0
## regardless of the real satiate() result.
func test_eat_larva_emits_the_real_overflow() -> void:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.hunger.current_hunger = 5.0 # eat_satiation (40) will overflow by 35
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	add_child_autofree(larva)
	watch_signals(EventBus)
	enemy._eat_larva(larva)
	assert_signal_emitted_with_parameters(EventBus, "larva_consumed", [enemy, 35.0])
