extends GutTest
## Round win: the player gets a partial heal (not a full reset) before
## carrying vitals forward and descending — winning a close fight shouldn't
## mean starting the next one already nearly dead.

const WorldScene := preload("res://world/world.tscn")


func test_enemy_defeated_heals_a_fraction_of_missing_health() -> void:
	var world := WorldScene.instantiate()
	add_child_autofree(world)
	await get_tree().process_frame

	var player := world._current_player() as Player
	player.health.current_health = 10.0 # nearly dead
	world.victory_heal_fraction = 0.5
	world._on_enemy_defeated("killed")

	# missing = 100 - 10 = 90; heal 90 * 0.5 = 45 -> 10 + 45 = 55
	assert_almost_eq(player.health.current_health, 55.0, 0.001)


func test_enemy_defeated_does_not_overheal_past_max() -> void:
	var world := WorldScene.instantiate()
	add_child_autofree(world)
	await get_tree().process_frame

	var player := world._current_player() as Player
	player.health.current_health = player.health.max_health # already full
	world._on_enemy_defeated("killed")
	assert_almost_eq(player.health.current_health, player.health.max_health, 0.001)
