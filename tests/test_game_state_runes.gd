extends GutTest
## GameState's rune currency (design §5: Economy) — earn/spend, the
## buy_upgrade() spend path, and that the balance survives a run reset the
## same way player_wins/enemy_wins already do.


func before_each() -> void:
	# Defensive reset, not just after_each: GameState now also earns runes off
	# EventBus.enemy_defeated/excess_consumed, which other test files emit —
	# start each test from a known-zero balance regardless of run order.
	GameState.runes = 0
	GameState.purchased_upgrades = []


func after_each() -> void:
	GameState.runes = 0
	GameState.purchased_upgrades = []


func test_earn_runes_increases_balance() -> void:
	GameState.earn_runes(50)
	assert_eq(GameState.runes, 50)


func test_earn_runes_ignores_non_positive_amounts() -> void:
	GameState.earn_runes(0)
	GameState.earn_runes(-5)
	assert_eq(GameState.runes, 0)


func test_spend_runes_succeeds_within_balance() -> void:
	GameState.earn_runes(100)
	assert_true(GameState.spend_runes(40))
	assert_eq(GameState.runes, 60)


func test_spend_runes_fails_over_balance() -> void:
	GameState.earn_runes(10)
	assert_false(GameState.spend_runes(20))
	assert_eq(GameState.runes, 10, "a failed spend never touches the balance")


func test_buy_upgrade_charges_and_records_it() -> void:
	GameState.earn_runes(100)
	var upgrade := UpgradeCatalog.new()
	upgrade.upgrade_id = &"max_health_up"
	upgrade.rune_cost = 60
	assert_true(GameState.buy_upgrade(upgrade))
	assert_eq(GameState.runes, 40)
	assert_true(&"max_health_up" in GameState.purchased_upgrades)


func test_buy_upgrade_twice_only_charges_once() -> void:
	GameState.earn_runes(200)
	var upgrade := UpgradeCatalog.new()
	upgrade.upgrade_id = &"max_health_up"
	upgrade.rune_cost = 60
	assert_true(GameState.buy_upgrade(upgrade))
	assert_false(GameState.buy_upgrade(upgrade), "already purchased")
	assert_eq(GameState.runes, 140)


func test_buy_upgrade_fails_when_unaffordable() -> void:
	GameState.earn_runes(10)
	var upgrade := UpgradeCatalog.new()
	upgrade.upgrade_id = &"max_health_up"
	upgrade.rune_cost = 60
	assert_false(GameState.buy_upgrade(upgrade))
	assert_eq(GameState.runes, 10)


func test_runes_survive_a_new_run_permadeath_reset() -> void:
	GameState.earn_runes(75)
	GameState.start_new_run()
	assert_eq(GameState.runes, 75, "currency is session-long, like the win tally")


func test_enemy_defeated_earns_the_round_win_bonus() -> void:
	EventBus.enemy_defeated.emit("killed")
	assert_eq(GameState.runes, GameState.ROUND_WIN_RUNES)


func test_excess_consumed_earns_runes_proportional_to_the_overflow() -> void:
	EventBus.excess_consumed.emit(null, 12.7)
	assert_eq(GameState.runes, 12, "fractional overflow truncates to whole runes")
