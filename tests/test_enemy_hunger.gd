extends GutTest
## Guards the enemy hunger re-retune: hunger_rate was cut from 3.0 to 1.2 when
## the old AI couldn't reliably feed itself, then restored to 3.0 once the AI
## motivation pass (purposeful patrol, state stickiness) made it proactive
## enough to sustain the original rate — confirmed empirically via a 300-second
## real-AI simulation (no health loss up to rate 5.0; it only starts to
## struggle at 7.0+), so 3.0 keeps a healthy margin, not just barely surviving.


func test_rival_hunger_rate_matches_the_ai_motivation_pass() -> void:
	var rival: EnemyType = preload("res://resources/enemies/rival_spider.tres")
	assert_almost_eq(rival.hunger_rate, 3.0, 0.001,
		"restored once the improved AI could sustain the original rate")


func test_periodic_feeding_prevents_starvation() -> void:
	# Simulate: hunger rises at the rival rate; a meal every ~8s keeps it below max.
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.hunger_rate = 3.0
	hunger.current_hunger = 0.0
	autofree(hunger)
	var t := 0.0
	while t < 60.0:
		hunger.tick(0.5)
		t += 0.5
		if fmod(t, 8.0) < 0.5: # a contact meal roughly every 8 seconds
			hunger.satiate(40.0)
	assert_false(hunger.is_starving(),
		"a fed enemy at hunger_rate 3.0 does not starve")
