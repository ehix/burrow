extends GutTest
## TinySpiderling (design §3): chases the nearest non-owner spider and
## attacks on contact until its lifetime elapses. Spawned by HatchlingsSkill
## (scouting) or CocoonMine's burst (ambush) — this only tests the shared
## entity, not either caller.

const SpiderlingScene := preload("res://entities/skills/scenes/tiny_spiderling.tscn")


func _make_spiderling() -> TinySpiderling:
	var spiderling: TinySpiderling = SpiderlingScene.instantiate()
	add_child_autofree(spiderling)
	return spiderling


func _make_target() -> Node2D:
	var target := Node2D.new()
	target.add_to_group("spiders")
	add_child_autofree(target)
	var health := HealthComponent.new()
	# _ready() (which seeds current_health from max_health) never runs on a
	# node that's never parented — set it explicitly, same as
	# test_hunger_component.gd's own HealthComponent test double.
	health.current_health = health.max_health
	autofree(health)
	var hurtbox := Hurtbox.new()
	hurtbox.health = health
	# A runtime-created node isn't auto-named after its class_name (that only
	# happens for nodes placed in a .tscn) — TinySpiderling._attack() looks it
	# up as "Hurtbox" by name, same as every real spider scene wires it.
	hurtbox.name = "Hurtbox"
	target.add_child(hurtbox)
	return target


func test_joins_the_hatchlings_group() -> void:
	var spiderling := _make_spiderling()
	assert_true(spiderling.is_in_group("hatchlings"))


func test_expires_after_its_lifetime() -> void:
	var spiderling := _make_spiderling()
	spiderling.setup(null, 1.0)
	spiderling._physics_process(0.6)
	assert_false(spiderling.is_queued_for_deletion())
	spiderling._physics_process(0.5)
	assert_true(spiderling.is_queued_for_deletion())


func test_attacks_the_nearest_non_owner_spider_on_contact() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	var target := _make_target()
	target.global_position = spiderling.global_position + Vector2(5, 0) # within attack_range
	spiderling.setup(owner_spider, 5.0)

	spiderling._physics_process(0.016)

	var health: HealthComponent = (target.get_node("Hurtbox") as Hurtbox).health
	assert_lt(health.current_health, health.max_health, "the target took damage on contact")


func test_never_targets_its_own_owner() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	owner_spider.global_position = spiderling.global_position # in contact range
	spiderling.setup(owner_spider, 5.0)

	spiderling._physics_process(0.016)

	var health: HealthComponent = (owner_spider.get_node("Hurtbox") as Hurtbox).health
	assert_eq(health.current_health, health.max_health, "the owner is never targeted")


func test_attack_respects_its_own_cooldown() -> void:
	var spiderling := _make_spiderling()
	var target := _make_target()
	target.global_position = spiderling.global_position
	spiderling.setup(null, 5.0)
	spiderling.attack_cooldown = 1.0

	spiderling._physics_process(0.016)
	var health: HealthComponent = (target.get_node("Hurtbox") as Hurtbox).health
	var after_first := health.current_health
	spiderling._physics_process(0.016) # still on cooldown
	assert_eq(health.current_health, after_first, "no second hit before the cooldown elapses")


func _make_wall(at: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 48)
	shape.shape = rect
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = at
	return wall


func test_default_move_speed_is_180() -> void:
	var spiderling := _make_spiderling()
	assert_eq(spiderling.move_speed, 180.0)


func test_escorts_toward_the_owner_plus_offset_when_no_enemy_is_near() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	owner_spider.global_position = Vector2(600, 600)
	spiderling.global_position = Vector2(0, 0)
	spiderling.setup(owner_spider, 5.0, Vector2(20, 0))
	var target_point := owner_spider.global_position + Vector2(20, 0)
	var before := spiderling.global_position.distance_to(target_point)

	for i in 10:
		spiderling._physics_process(0.05)

	var after := spiderling.global_position.distance_to(target_point)
	assert_lt(after, before, "the hatchling steps toward its owner's escort point")


func test_switches_to_chase_when_an_enemy_enters_aggro_radius_and_los() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	owner_spider.global_position = Vector2(2000, 2000) # far away, irrelevant
	var enemy := _make_target()
	spiderling.global_position = Vector2(0, 0)
	enemy.global_position = Vector2(50, 0) # within aggro_radius(180), beyond attack_range(20)
	spiderling.setup(owner_spider, 5.0)

	spiderling._physics_process(0.016)

	assert_gt(spiderling.velocity.length(), 0.0, "the hatchling moves toward the visible enemy instead of escorting")


func test_never_targets_an_enemy_blocked_by_a_wall() -> void:
	var spiderling := _make_spiderling()
	var enemy := _make_target()
	spiderling.global_position = Vector2(0, 0)
	enemy.global_position = Vector2(100, 0)
	_make_wall(Vector2(50, 0))
	spiderling.setup(null, 5.0) # no owner -> escort() with no owner holds still

	spiderling._physics_process(0.016)

	assert_eq(spiderling.velocity, Vector2.ZERO, "a wall-blocked enemy is never targeted")


func test_reverts_to_escort_once_the_target_leaves_aggro_radius() -> void:
	var spiderling := _make_spiderling()
	var owner_spider := _make_target()
	owner_spider.global_position = Vector2(0, 0)
	var enemy := _make_target()
	spiderling.global_position = Vector2(0, 0)
	enemy.global_position = Vector2(50, 0)
	spiderling.setup(owner_spider, 5.0)
	spiderling._physics_process(0.016)
	assert_gt(spiderling.velocity.length(), 0.0, "starts chasing")

	enemy.global_position = Vector2(5000, 5000) # far outside aggro_radius
	# Converge over several ticks rather than asserting on one exact instant
	# right after the switch — move_and_slide() uses the engine's own
	# physics delta, not the value passed here, so a single-tick distance
	# check would be too tightly coupled to that exact timing.
	for i in 20:
		spiderling._physics_process(0.05)

	assert_lt(spiderling.global_position.distance_to(owner_spider.global_position), 1.0,
		"settles back at the owner's position once escort resumes (no target, escort_offset defaults to zero)")
