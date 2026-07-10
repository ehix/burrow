extends GutTest
## Player.apply_class() (design §3, dev tool Q): swaps stat multipliers and
## which class-specific skills respond to input, live, without restarting.

const PlayerScene := preload("res://entities/player/player.tscn")


func _make_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	return player


func test_defaults_to_wolf() -> void:
	var player := _make_player()
	assert_eq(player._active_class, SpiderClassData.SpiderClass.WOLF)


func test_apply_class_scales_melee_damage_from_the_base_value() -> void:
	var player := _make_player()
	var base := player._base_melee_damage
	player.apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_almost_eq(player.melee_damage, base * Player.NetCasterData.melee_damage_mult, 0.001)


func test_switching_classes_never_compounds() -> void:
	var player := _make_player()
	var base := player._base_melee_damage
	player.apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	player.apply_class(SpiderClassData.SpiderClass.DECOY)
	player.apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_almost_eq(player.melee_damage, base * Player.NetCasterData.melee_damage_mult, 0.001,
		"repeated switching is always relative to the untouched base, never the last class's numbers")


func test_net_caster_disables_standard_web_shooting() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_false(player._active_class_data.web_enabled)


func test_other_classes_keep_web_shooting_enabled() -> void:
	var player := _make_player()
	for spider_class in [SpiderClassData.SpiderClass.WOLF, SpiderClassData.SpiderClass.WEAVER, SpiderClassData.SpiderClass.DECOY]:
		player.apply_class(spider_class)
		assert_true(player._active_class_data.web_enabled)


func test_is_active_skill_only_true_for_the_current_classs_own_skills() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WOLF)
	assert_true(player._is_active_skill("hatchlings"))
	assert_true(player._is_active_skill("egg_mine"))
	assert_false(player._is_active_skill("camouflage"), "Camouflage belongs to Decoy, not Wolf")


func test_unknown_class_id_is_a_noop() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WEAVER)
	var before := player.melee_damage
	player.apply_class(999) # not a real class id
	assert_eq(player.melee_damage, before, "an unrecognised id leaves the current class untouched")


func test_net_shot_is_free_to_fire() -> void:
	# Net Hold already charges the real "engagement fee" (cost + cooldown) to
	# arm yourself with a trap. Net Shot is just deciding how to discharge
	# what you already paid for, so it costs nothing extra — re-arming via
	# Net Hold is what naturally throttles repeated throws, not a second,
	# redundant cost on the throw itself.
	var player := _make_player()
	assert_eq(player._net_shot.hunger_cost, 0.0, "throwing an already-held trap costs nothing extra")
	assert_eq(player._net_shot.cooldown, 0.0, "no independent cooldown — re-arming via Net Hold is the real gate")
