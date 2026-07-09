extends GutTest
## HUD routes health/hunger updates to the player or enemy bars by group
## membership, and shows a round-result banner + updates the win tally when
## a depth ends (enemy defeated = a player win, player died = an enemy win).

const HudScene := preload("res://ui/hud.tscn")


func after_each() -> void:
	GameState.player_wins = 0
	GameState.enemy_wins = 0 # don't leak into other tests


func _make_hud() -> Node:
	var hud := HudScene.instantiate()
	add_child_autofree(hud)
	return hud


func _make_spider(group: String) -> Node2D:
	var node := Node2D.new()
	node.add_to_group(group)
	autofree(node)
	return node


func test_health_changed_routes_by_group() -> void:
	var hud := _make_hud()
	hud._on_health_changed(_make_spider("player"), 40.0, 100.0)
	assert_eq(hud.health_bar.value, 40.0)
	hud._on_health_changed(_make_spider("enemy"), 25.0, 80.0)
	assert_eq(hud.enemy_health_bar.value, 25.0)
	assert_eq(hud.enemy_health_bar.max_value, 80.0)


func test_hunger_changed_routes_by_group() -> void:
	var hud := _make_hud()
	hud._on_hunger_changed(_make_spider("player"), 30.0, 100.0)
	assert_eq(hud.hunger_bar.value, 30.0)
	hud._on_hunger_changed(_make_spider("enemy"), 55.0, 100.0)
	assert_eq(hud.enemy_hunger_bar.value, 55.0)


func test_enemy_defeated_counts_as_a_player_win() -> void:
	_make_hud()
	EventBus.enemy_defeated.emit("killed")
	assert_eq(GameState.player_wins, 1)


func test_player_died_counts_as_an_enemy_win() -> void:
	_make_hud()
	EventBus.player_died.emit()
	assert_eq(GameState.enemy_wins, 1)


func test_enemy_defeated_updates_the_wins_label_and_shows_a_banner() -> void:
	var hud := _make_hud()
	EventBus.enemy_defeated.emit("killed")
	assert_eq(hud.wins_label.text, "Wins: You 1 - Enemy 0")
	assert_eq(hud.round_banner_label.text, "ENEMY DEFEATED!")
	assert_almost_eq(hud.round_banner_label.modulate.a, 1.0, 0.001, "banner is fully visible right away")


func test_player_died_updates_the_wins_label_and_shows_a_banner() -> void:
	var hud := _make_hud()
	EventBus.player_died.emit()
	assert_eq(hud.wins_label.text, "Wins: You 0 - Enemy 1")
	assert_eq(hud.round_banner_label.text, "YOU DIED")
	assert_almost_eq(hud.round_banner_label.modulate.a, 1.0, 0.001, "banner is fully visible right away")
