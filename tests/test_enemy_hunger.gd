extends GutTest
## Guards the enemy hunger retune: the rival's configured hunger_rate is slow
## enough that periodic feeding keeps it alive.


func test_rival_hunger_rate_is_retuned() -> void:
	var rival: EnemyType = preload("res://resources/enemies/rival_spider.tres")
	assert_almost_eq(rival.hunger_rate, 1.2, 0.001,
		"rival hunger_rate lowered so it can feed itself")


func test_periodic_feeding_prevents_starvation() -> void:
	# Simulate: hunger rises at the rival rate; a meal every ~8s keeps it below max.
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.hunger_rate = 1.2
	hunger.current_hunger = 0.0
	autofree(hunger)
	var t := 0.0
	while t < 60.0:
		hunger.tick(0.5)
		t += 0.5
		if fmod(t, 8.0) < 0.5: # a contact meal roughly every 8 seconds
			hunger.satiate(40.0)
	assert_false(hunger.is_starving(),
		"a fed enemy at hunger_rate 1.2 does not starve")
