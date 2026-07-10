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
