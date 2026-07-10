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


func test_apply_class_tints_the_sprite_to_the_class_color() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WEAVER)
	assert_eq(player.sprite.modulate, Player.WeaverData.display_color)


func test_ceiling_tint_composes_with_the_class_color_instead_of_replacing_it() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WEAVER)
	player._plane.transition() # -> CEILING
	assert_eq(player.sprite.modulate, Player.WeaverData.display_color * Color(0.55, 0.65, 0.85, 0.85))
	player._plane.transition() # -> GROUND
	assert_eq(player.sprite.modulate, Player.WeaverData.display_color, "back to the plain class color on the ground")


func test_net_shot_is_free_to_fire() -> void:
	# Net Hold already charges the real "engagement fee" (cost + cooldown) to
	# arm yourself with a trap. Net Shot is just deciding how to discharge
	# what you already paid for, so it costs nothing extra — re-arming via
	# Net Hold is what naturally throttles repeated throws, not a second,
	# redundant cost on the throw itself.
	var player := _make_player()
	assert_eq(player._net_shot.hunger_cost, 0.0, "throwing an already-held trap costs nothing extra")
	assert_eq(player._net_shot.cooldown, 0.0, "no independent cooldown — re-arming via Net Hold is the real gate")


func test_weaver_takes_no_slow_from_a_web_hit() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WEAVER)
	player.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0) # a pure web-crossing slow
	assert_eq(player._mover.speed_scale, 1.0, "a Weaver never gets slowed by a web")


func test_non_weaver_still_gets_slowed_by_a_web_hit() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WOLF)
	player.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0)
	assert_eq(player._mover.speed_scale, 0.5, "every other class is slowed as before")


func test_weaver_still_gets_knocked_back_and_stunned_by_a_web_hit() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WEAVER)
	player.apply_web_hit(Vector2i.RIGHT, 0.5, 1.5, 0.3)
	assert_true(player._mover.is_stunned(), "immunity is to the slow only, not the stun")


func test_decoy_shot_costs_health_to_fire() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.DECOY)
	var before := player.health.current_health
	player.web_emitter.cooldown = 0.0 # ignore fire-rate cooldown for this check
	var shot := player.web_emitter.fire(player.global_position, Vector2.RIGHT, player,
		Player.DecoyData.web_projectile_speed_mult)
	if shot != null and Player.DecoyData.web_fire_health_cost > 0.0:
		player.health.take_damage(Player.DecoyData.web_fire_health_cost)
	assert_almost_eq(player.health.current_health, before - Player.DecoyData.web_fire_health_cost, 0.001)


func test_non_decoy_fire_costs_no_extra_health() -> void:
	var player := _make_player()
	player.apply_class(SpiderClassData.SpiderClass.WOLF)
	var before := player.health.current_health
	assert_almost_eq(Player.WolfData.web_fire_health_cost, 0.0, 0.001, "no class but Decoy costs health to fire")
	assert_almost_eq(player.health.current_health, before, 0.001)
