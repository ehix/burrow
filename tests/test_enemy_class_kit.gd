extends GutTest
## Enemy's class kit (design §2/§3): each class scales melee/web stats and
## attaches its two skills, mirroring Player.apply_class(). A periodic
## utility-scoring check (EnemyUtilityAI) then decides whether to actually
## use one, based on the enemy's current state.

const EnemyScene := preload("res://entities/enemy/enemy.tscn")


func after_each() -> void:
	GameState.depth = GameState.STARTING_DEPTH # don't leak into other tests


func _make_enemy() -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	return enemy


func test_apply_class_scales_melee_damage_from_the_base_value() -> void:
	var enemy := _make_enemy()
	var base := enemy._base_melee_damage
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_almost_eq(enemy.melee_damage, base * Enemy.NetCasterData.melee_damage_mult, 0.001)


func test_switching_classes_never_compounds() -> void:
	var enemy := _make_enemy()
	var base := enemy._base_melee_damage
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	enemy._apply_class(SpiderClassData.SpiderClass.DECOY)
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_almost_eq(enemy.melee_damage, base * Enemy.NetCasterData.melee_damage_mult, 0.001)


func test_net_caster_disables_web_firing() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_false(enemy._web_enabled())


func test_other_classes_keep_web_firing_enabled() -> void:
	var enemy := _make_enemy()
	for spider_class in [SpiderClassData.SpiderClass.WOLF, SpiderClassData.SpiderClass.WEAVER, SpiderClassData.SpiderClass.DECOY]:
		enemy._apply_class(spider_class)
		assert_true(enemy._web_enabled())


func test_net_caster_gets_net_hold_and_net_shot() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	assert_eq(enemy._skills.size(), 2)
	assert_true(enemy._skills[0] is NetHoldSkill)
	assert_true(enemy._skills[1] is NetShotSkill)


func test_net_shot_is_wired_to_its_sibling_net_hold() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	var shot: NetShotSkill = enemy._skills[1]
	assert_eq(shot.net_hold, enemy._skills[0])


func test_wolf_gets_hatchlings_and_egg_mine() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)
	assert_true(enemy._skills[0] is HatchlingsSkill)
	assert_true(enemy._skills[1] is EggMineSkill)


func test_weaver_gets_blockade_and_silk_tunnel() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WEAVER)
	assert_true(enemy._skills[0] is BlockadeSkill)
	assert_true(enemy._skills[1] is SilkTunnelSkill)


func test_decoy_gets_camouflage_and_decoy() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.DECOY)
	assert_true(enemy._skills[0] is CamouflageSkill)
	assert_true(enemy._skills[1] is DecoySkill)


func test_apply_class_tints_the_sprite_to_the_class_color() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.DECOY)
	assert_eq(enemy.facing_visual.modulate, Enemy.DecoyClassData.display_color)


func test_apply_class_swaps_the_sprite_texture_to_the_new_classs_art() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.DECOY)
	assert_eq(enemy.facing_visual.texture, Enemy.DecoyClassData.frame_for_facing(enemy.facing))


## Mirrors test_player_class_switching.gd's own test -- see its comment for
## why this matters (Ogre/Decoy's leaner crops read smaller than Wolf's
## stocky one under a flat scale factor).
func test_every_class_normalizes_to_the_same_on_screen_sprite_extent() -> void:
	var enemy := _make_enemy()
	var extent: float = Enemy.SPRITE_TARGET_EXTENT_PX
	var sprite := enemy.facing_visual as Sprite2D
	for spider_class in [SpiderClassData.SpiderClass.NET_CASTER, SpiderClassData.SpiderClass.WOLF,
			SpiderClassData.SpiderClass.WEAVER, SpiderClassData.SpiderClass.DECOY]:
		enemy._apply_class(spider_class)
		var tex_size := sprite.texture.get_size()
		var effective := sprite.scale.x * maxf(tex_size.x, tex_size.y)
		assert_almost_eq(effective, extent, 0.5,
			"class %d's sprite should read as the same size as every other class's" % spider_class)


func test_facing_changes_swap_the_sprite_frame_instead_of_rotating() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)

	enemy._face(Vector2i.LEFT)
	assert_eq(enemy.facing_visual.texture, Enemy.WolfData.sprite_west)
	assert_false((enemy.facing_visual as Sprite2D).flip_h, "facing left uses the west texture unflipped")
	assert_eq(enemy.facing_visual.rotation, 0.0, "the sprite never rotates now -- baked art carries the facing")

	enemy._face(Vector2i.UP)
	assert_eq(enemy.facing_visual.texture, Enemy.WolfData.sprite_north)


## There is no separate EAST texture (see SpiderClassData's own doc comment
## for why) -- facing right reuses the west texture, mirrored.
func test_facing_right_reuses_the_west_texture_flipped() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)

	enemy._face(Vector2i.RIGHT)

	assert_eq(enemy.facing_visual.texture, Enemy.WolfData.sprite_west)
	assert_true((enemy.facing_visual as Sprite2D).flip_h, "facing right mirrors the same west texture")
	assert_eq(enemy.facing_visual.rotation, 0.0)


func test_switching_classes_frees_the_old_skills() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)
	var old_skills := enemy._skills.duplicate()
	enemy._apply_class(SpiderClassData.SpiderClass.WEAVER)
	for skill in old_skills:
		assert_true(skill.is_queued_for_deletion())


func test_emits_enemy_class_changed() -> void:
	var enemy := _make_enemy()
	var seen: Array = []
	EventBus.enemy_class_changed.connect(func(spider_class: int) -> void: seen.append(spider_class))
	enemy._apply_class(SpiderClassData.SpiderClass.DECOY)
	assert_has(seen, SpiderClassData.SpiderClass.DECOY)


func test_score_skill_favors_combat_skills_during_chase_with_a_target() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)
	enemy.state = Enemy.State.CHASE
	enemy._current_target = Node2D.new()
	add_child_autofree(enemy._current_target)
	for skill in enemy._skills:
		assert_gt(enemy._score_skill(skill), 0.0)


func test_score_skill_is_zero_outside_chase_for_combat_skills() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)
	enemy.state = Enemy.State.PATROL
	for skill in enemy._skills:
		assert_eq(enemy._score_skill(skill), 0.0)


func test_score_skill_favors_defensive_skills_while_fleeing() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.DECOY)
	enemy.state = Enemy.State.FLEE
	for skill in enemy._skills:
		assert_gt(enemy._score_skill(skill), 0.0)


func test_score_skill_net_shot_only_scores_while_holding_a_trap() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	enemy.state = Enemy.State.CHASE
	enemy._current_target = Node2D.new()
	add_child_autofree(enemy._current_target)
	var shot: NetShotSkill = enemy._skills[1]

	assert_eq(enemy._score_skill(shot), 0.0, "not holding — nothing to fire")

	shot.net_hold.holding = true
	assert_gt(enemy._score_skill(shot), 0.0, "holding — worth firing")


func test_net_shot_is_free_to_fire() -> void:
	# Net Hold already charges the real "engagement fee" to arm a trap; Net
	# Shot is just discharging what's already held, so it costs nothing
	# extra — re-arming via Net Hold is the natural throttle, not a second
	# cost on the throw itself.
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.NET_CASTER)
	var shot: NetShotSkill = enemy._skills[1]

	assert_eq(shot.hunger_cost, 0.0, "throwing an already-held trap costs nothing extra")
	assert_eq(shot.cooldown, 0.0, "no independent cooldown — re-arming via Net Hold is the real gate")


func test_nearest_pickupable_trap_finds_a_trap_within_range() -> void:
	var enemy := _make_enemy()
	var trap := WebTrap.new()
	add_child_autofree(trap)
	trap.setup(enemy)
	trap.global_position = enemy.global_position

	assert_eq(enemy._nearest_pickupable_trap(), trap, "found even though nothing's caught in it yet")


func test_nearest_pickupable_trap_finds_a_trap_regardless_of_owner() -> void:
	var enemy := _make_enemy()
	var other := Node2D.new()
	add_child_autofree(other)
	var trap := WebTrap.new()
	add_child_autofree(trap)
	trap.setup(other) # laid by someone else entirely
	trap.global_position = enemy.global_position

	assert_eq(enemy._nearest_pickupable_trap(), trap, "any trap on the map is pickupable, not just the enemy's own")


func test_consider_using_a_skill_activates_the_tied_winner_deterministically() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)
	enemy.state = Enemy.State.CHASE
	enemy._current_target = Node2D.new()
	add_child_autofree(enemy._current_target)
	# At max depth_intel (deepest depth), a qualifying skill's score (0.6)
	# clears the "do nothing extra" baseline (0.35) — at the default depth 1
	# it wouldn't (0.6 * 0.525 = 0.315 < 0.35), which is the depth-scaling
	# guardrail working as intended, not a fluke of this test.
	GameState.depth = 20

	enemy._consider_using_a_skill()

	assert_false(enemy._skills[0].can_activate(), "Hatchlings (first, tied-highest score) was activated")
	assert_true(enemy._skills[1].can_activate(), "only one candidate wins")


func test_shallow_depth_favors_the_baseline_over_a_qualifying_skill() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)
	enemy.state = Enemy.State.CHASE
	enemy._current_target = Node2D.new()
	add_child_autofree(enemy._current_target)
	GameState.depth = GameState.STARTING_DEPTH # depth 1: low depth_intel

	enemy._consider_using_a_skill()

	for skill in enemy._skills:
		assert_true(skill.can_activate(),
			"a shallow enemy is less eager to use its kit — the guardrail scaling in action")


func test_consider_using_a_skill_does_nothing_when_no_skill_qualifies() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)
	enemy.state = Enemy.State.PATROL

	enemy._consider_using_a_skill()

	for skill in enemy._skills:
		assert_true(skill.can_activate(), "no skill should fire outside its applicable state")


func test_weaver_enemy_takes_no_slow_from_a_web_hit() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WEAVER)
	enemy.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0)
	assert_eq(enemy._mover.speed_scale, 1.0, "a Weaver enemy never gets slowed by a web")


func test_non_weaver_enemy_still_gets_slowed_by_a_web_hit() -> void:
	var enemy := _make_enemy()
	enemy._apply_class(SpiderClassData.SpiderClass.WOLF)
	enemy.apply_web_hit(Vector2i.ZERO, 0.5, 1.5, 0.0)
	assert_eq(enemy._mover.speed_scale, 0.5, "every other class is slowed as before")


func test_decoy_has_a_nonzero_fire_health_cost() -> void:
	assert_gt(Enemy.DecoyClassData.web_fire_health_cost, 0.0)


func test_other_classes_have_no_fire_health_cost() -> void:
	for data in [Enemy.NetCasterData, Enemy.WolfData, Enemy.WeaverData]:
		assert_almost_eq(data.web_fire_health_cost, 0.0, 0.001)
