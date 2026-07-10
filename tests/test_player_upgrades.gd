extends GutTest
## Player's permanent-upgrade purchase flow (design §5, keys 1-4):
## GameState.buy_upgrade() is the only spend path; a successful purchase
## refreshes stats immediately via refresh_upgrades(), which is idempotent
## and composes correctly with class multipliers.

const PlayerScene := preload("res://entities/player/player.tscn")


func _make_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func before_each() -> void:
	GameState.runes = 0
	GameState.purchased_upgrades = []


func after_each() -> void:
	GameState.runes = 0
	GameState.purchased_upgrades = []


func test_buying_vitality_boost_raises_max_health() -> void:
	var player := _make_player()
	var before := player.health.max_health
	GameState.earn_runes(200)

	player._try_buy_upgrade(0) # vitality_boost

	assert_almost_eq(player.health.max_health, before + 20.0, 0.001)


func test_buying_iron_fangs_raises_melee_damage() -> void:
	var player := _make_player()
	var before := player.melee_damage
	GameState.earn_runes(200)

	player._try_buy_upgrade(1) # iron_fangs

	assert_almost_eq(player.melee_damage, before + 4.0, 0.001)


func test_buying_rapid_silk_lowers_web_cooldown() -> void:
	var player := _make_player()
	var before := player.web_emitter.cooldown
	GameState.earn_runes(200)

	player._try_buy_upgrade(2) # rapid_silk

	assert_almost_eq(player.web_emitter.cooldown, before - 0.1, 0.001)


func test_buying_slow_metabolism_lowers_hunger_rate() -> void:
	var player := _make_player()
	var before := player.hunger.hunger_rate
	GameState.earn_runes(200)

	player._try_buy_upgrade(3) # slow_metabolism

	assert_almost_eq(player.hunger.hunger_rate, before - 0.5, 0.001)


func test_purchase_fails_silently_when_unaffordable() -> void:
	var player := _make_player()
	var before := player.health.max_health
	GameState.runes = 0 # vitality_boost costs 80

	player._try_buy_upgrade(0)

	assert_eq(player.health.max_health, before)
	assert_eq(GameState.runes, 0)


func test_out_of_range_index_is_a_noop() -> void:
	var player := _make_player()
	GameState.earn_runes(500)
	player._try_buy_upgrade(99) # must not error
	assert_eq(GameState.purchased_upgrades.size(), 0)


func test_purchase_emits_upgrade_purchased() -> void:
	var player := _make_player()
	GameState.earn_runes(200)
	var seen: Array = []
	EventBus.upgrade_purchased.connect(func(id: StringName) -> void: seen.append(id))

	player._try_buy_upgrade(0)

	assert_has(seen, &"vitality_boost")


func test_refresh_upgrades_is_idempotent() -> void:
	var player := _make_player()
	GameState.earn_runes(200)
	player._try_buy_upgrade(1) # iron_fangs: +4 melee damage
	var after_purchase := player.melee_damage

	player.refresh_upgrades()
	player.refresh_upgrades()
	player.refresh_upgrades()

	assert_almost_eq(player.melee_damage, after_purchase, 0.001,
		"repeated refreshes never compound the same purchased upgrade")


func test_upgrades_persist_and_compose_across_a_class_switch() -> void:
	var player := _make_player()
	GameState.earn_runes(200)
	player._try_buy_upgrade(1) # iron_fangs: +4 melee damage

	player.apply_class(SpiderClassData.SpiderClass.NET_CASTER)

	var expected := (player._base_melee_damage + 4.0) * Player.NetCasterData.melee_damage_mult
	assert_almost_eq(player.melee_damage, expected, 0.001)
