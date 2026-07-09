extends GutTest
## GameState carried-vitals lifecycle: dev reset map treats it as a fresh
## spawn, not a carried-forward descent.


func after_each() -> void:
	GameState.clear_carried_vitals() # don't leak into other tests
	GameState.player_wins = 0
	GameState.enemy_wins = 0


func test_clear_carried_vitals_resets_to_uninitialised() -> void:
	GameState.carried_health = 42.0
	GameState.carried_hunger = 10.0
	GameState.clear_carried_vitals()
	assert_false(GameState.has_carried_vitals(), "cleared vitals read as uninitialised")


func test_start_new_run_clears_carried_vitals() -> void:
	GameState.carried_health = 42.0
	GameState.carried_hunger = 10.0
	GameState.start_new_run(123)
	assert_false(GameState.has_carried_vitals())


func test_enemy_defeated_increments_player_wins() -> void:
	EventBus.enemy_defeated.emit("killed")
	assert_eq(GameState.player_wins, 1)


func test_player_died_increments_enemy_wins() -> void:
	EventBus.player_died.emit()
	assert_eq(GameState.enemy_wins, 1)


func test_win_tally_survives_a_new_run_permadeath_reset() -> void:
	# The tally is a session-long scoreboard — permadeath resets the run's
	# depth/vitals, not who's winning overall.
	GameState.player_wins = 3
	GameState.enemy_wins = 2
	GameState.start_new_run()
	assert_eq(GameState.player_wins, 3)
	assert_eq(GameState.enemy_wins, 2)
