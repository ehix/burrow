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


func test_nearest_own_ready_trap_finds_an_owned_trap_within_range() -> void:
	var enemy := _make_enemy()
	var trap := WebTrap.new()
	add_child_autofree(trap)
	trap.setup(enemy)
	trap.global_position = enemy.global_position

	assert_eq(enemy._nearest_own_ready_trap(), trap, "found even though nothing's caught in it yet")


func test_nearest_own_ready_trap_ignores_a_trap_owned_by_someone_else() -> void:
	var enemy := _make_enemy()
	var other := Node2D.new()
	add_child_autofree(other)
	var trap := WebTrap.new()
	add_child_autofree(trap)
	trap.setup(other)
	trap.global_position = enemy.global_position

	assert_null(enemy._nearest_own_ready_trap())


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
