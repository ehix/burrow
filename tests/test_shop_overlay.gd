extends GutTest
## ShopOverlay (UI/HUD overhaul): lists every upgrade with cost/description,
## dimming rows the player can't yet afford. Purely informational — never
## spends runes itself, purchase stays on the existing buy_upgrade_1-4 keys.

const ShopOverlayScene := preload("res://ui/shop_overlay.tscn")


func after_each() -> void:
	GameState.runes = 0 # don't leak into other tests


func _make_shop() -> ShopOverlay:
	var shop: ShopOverlay = ShopOverlayScene.instantiate()
	add_child_autofree(shop)
	return shop


func test_hidden_by_default() -> void:
	var shop := _make_shop()
	assert_false(shop.visible)


func test_toggle_flips_visibility() -> void:
	var shop := _make_shop()
	shop.toggle()
	assert_true(shop.visible)
	shop.toggle()
	assert_false(shop.visible)


func test_lists_every_upgrade_with_name_and_cost() -> void:
	var shop := _make_shop()
	assert_eq(shop._row_labels.size(), UpgradeRegistry.ALL.size())
	var first := UpgradeRegistry.ALL[0]
	assert_true(shop._row_labels[0].text.contains(first.display_name))
	assert_true(shop._row_labels[0].text.contains(str(first.rune_cost)))


func test_dims_a_row_the_player_cannot_afford() -> void:
	var shop := _make_shop()
	GameState.runes = 0

	shop.refresh()

	assert_eq(shop._row_labels[0].modulate, ShopOverlay.UNAFFORDABLE_COLOR)


func test_undims_a_row_once_affordable() -> void:
	var shop := _make_shop()
	var first := UpgradeRegistry.ALL[0]
	GameState.runes = first.rune_cost

	shop.refresh()

	assert_eq(shop._row_labels[0].modulate, ShopOverlay.AFFORDABLE_COLOR)


func test_refreshes_automatically_when_runes_change() -> void:
	var shop := _make_shop()
	var first := UpgradeRegistry.ALL[0]

	# Mirror production: GameState always sets `runes` before emitting
	# runes_changed (see earn_runes/spend_runes in game_state.gd). refresh()
	# reads GameState.runes, so the signal alone (without the state mutation
	# that always precedes it in real usage) can't exercise this path.
	GameState.runes = first.rune_cost
	EventBus.runes_changed.emit(first.rune_cost)

	assert_eq(shop._row_labels[0].modulate, ShopOverlay.AFFORDABLE_COLOR)
