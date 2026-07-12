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


func test_bind_spiders_wires_the_skill_bar_and_status_rows() -> void:
	var hud := _make_hud()
	var player: Player = preload("res://entities/player/player.tscn").instantiate()
	add_child_autofree(player)
	var enemy := _make_spider("enemy")

	hud.bind_spiders(player, enemy)

	assert_eq(hud.skill_bar._name_label1.text, player._hatchlings.display_name)
	assert_not_null(hud.player_status_row._bound_spider)
	assert_eq(hud.enemy_status_row._bound_spider, enemy)


func test_bind_spiders_primes_the_inventory_icon_from_the_players_current_item() -> void:
	var hud := _make_hud()
	var player: Player = preload("res://entities/player/player.tscn").instantiate()
	add_child_autofree(player)
	var item := FungusSenseItem.new()
	player.inventory.held_item = item

	hud.bind_spiders(player, _make_spider("enemy"))

	assert_true(hud.inventory_icon.visible)
	assert_eq(hud.inventory_icon.modulate, ConsumableItem.ITEM_COLORS.get(item.item_id, Color.WHITE))


func test_inventory_icon_hides_when_the_held_item_clears() -> void:
	var hud := _make_hud()
	var player: Player = preload("res://entities/player/player.tscn").instantiate()
	add_child_autofree(player)
	hud.bind_spiders(player, _make_spider("enemy"))
	player.inventory.held_item = FungusSenseItem.new()
	player.inventory.item_held_changed.emit(player.inventory.held_item)
	assert_true(hud.inventory_icon.visible)

	player.inventory.held_item = null
	player.inventory.item_held_changed.emit(null)

	assert_false(hud.inventory_icon.visible)
