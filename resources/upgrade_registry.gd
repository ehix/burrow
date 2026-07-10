class_name UpgradeRegistry
extends RefCounted
## The full authored catalog of permanent upgrades (design §5) — every one
## the player can buy. Used to look an id back up to its effect data
## (Player.refresh_upgrades()) and to list what's for sale (ControlIndicators,
## the buy_upgrade_N dev keys).
##
## Kept as a separate script from UpgradeCatalog itself — a
## `const Array[UpgradeCatalog]` of UpgradeCatalog .tres resources declared
## *inside* upgrade_catalog.gd is a self-referential bootstrapping problem
## (the script needs to finish registering as a global class before a .tres
## naming it as `script_class` can deserialize against it, but the const
## array is itself part of that same script body being parsed).

const ALL: Array[UpgradeCatalog] = [
	preload("res://resources/upgrades/vitality_boost.tres"),
	preload("res://resources/upgrades/iron_fangs.tres"),
	preload("res://resources/upgrades/rapid_silk.tres"),
	preload("res://resources/upgrades/slow_metabolism.tres"),
]


static func by_id(upgrade_id: StringName) -> UpgradeCatalog:
	for upgrade in ALL:
		if upgrade.upgrade_id == upgrade_id:
			return upgrade
	return null
