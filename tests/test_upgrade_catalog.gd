extends GutTest
## UpgradeRegistry's authored list (design §5): every entry is findable by
## id, with a distinct id and a well-formed effect.


func test_all_four_upgrades_are_authored() -> void:
	assert_eq(UpgradeRegistry.ALL.size(), 4)


func test_every_upgrade_has_a_unique_id() -> void:
	var seen := {}
	for upgrade in UpgradeRegistry.ALL:
		assert_false(seen.has(upgrade.upgrade_id), "duplicate id: %s" % upgrade.upgrade_id)
		seen[upgrade.upgrade_id] = true


func test_by_id_finds_an_authored_upgrade() -> void:
	var found := UpgradeRegistry.by_id(&"vitality_boost")
	assert_not_null(found)
	assert_eq(found.display_name, "Vitality Boost")
	assert_eq(found.effect_stat, "max_health")


func test_by_id_returns_null_for_an_unknown_id() -> void:
	assert_null(UpgradeRegistry.by_id(&"not_a_real_upgrade"))


func test_every_upgrade_has_a_positive_rune_cost() -> void:
	for upgrade in UpgradeRegistry.ALL:
		assert_gt(upgrade.rune_cost, 0)
