extends GutTest
## Ground-only content parenting (tunnel visual rework Phase 2): larvae,
## world items, and hazard markers (see test_level_hazard_helpers.gd) get
## parented under GroundLayer instead of Entities/Level directly, so they
## read as part of the dimmable "hazy background" while the player is on
## the ceiling (see docs/superpowers/specs/2026-07-14-tunnel-visual-rework-
## design.md). Player/Enemy (plane-aware, dimmed individually via
## body_alpha instead) stay under Entities, unaffected -- and so do both
## Centipede types (correction, 2026-07-14): a Centipede's body is the same
## width as the tunnel itself, so it must read identically regardless of
## plane, unlike a loose larva or item -- dimming it as "background" would
## be wrong.

func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	return level


func test_spawned_larva_is_parented_under_ground_layer() -> void:
	var level := _make_level()
	var larvae := level.get_tree().get_nodes_in_group("larvae")
	assert_gt(larvae.size(), 0, "level.build() seeds at least one larva by default")
	assert_eq((larvae[0] as Node2D).get_parent(), level._ground_layer)


func test_spawned_world_item_is_parented_under_ground_layer() -> void:
	var level := _make_level()
	var items := level.get_tree().get_nodes_in_group("world_items")
	assert_gt(items.size(), 0, "level.build() seeds ITEM_SPAWN_COUNT items by default")
	assert_eq((items[0] as Node2D).get_parent(), level._ground_layer)


func test_spawned_centipede_stays_parented_under_entities_not_ground_layer() -> void:
	var level := _make_level()
	var centipedes := level.get_tree().get_nodes_in_group("centipedes")
	if centipedes.is_empty():
		pending("no valid chain existed on this maze seed -- not exercised this run")
		return
	assert_eq((centipedes[0] as Node2D).get_parent(), level._entities,
		"a Centipede's body spans the tunnel width -- it must read the same on both planes, not dim as background")


func test_centipede_express_rider_stays_parented_under_entities_not_ground_layer() -> void:
	var level := _make_level()
	var entry: Vector2i = level.maze.open_cells()[0]

	level.spawn_centipede_express_rider(entry, Vector2i.RIGHT)

	var riders := level.get_tree().get_nodes_in_group("centipede_express_riders")
	assert_eq(riders.size(), 1)
	assert_eq((riders[0] as Node2D).get_parent(), level._entities)


func test_player_and_enemy_stay_parented_under_entities() -> void:
	var level := _make_level()
	assert_eq(level.player.get_parent(), level._entities)
	assert_eq(level.enemy.get_parent(), level._entities)
