extends GutTest
## CocoonMine (skill fixes bundle): a hidden proximity trap. Deals direct
## burst_damage to whatever spider crosses it, then spawns a cosmetic burst
## of MineSpiderlings — larvae are immune, and it only triggers for a body
## on the same plane it was armed on.

## PlayerScene is preloaded before MineScene deliberately: cocoon_mine.gd's
## Level.Layer typing pulls in level.gd, which itself preloads player.tscn
## (an ext_resource of cocoon_mine.tscn) — loading MineScene first re-enters
## cocoon_mine.tscn's own in-flight load and Godot reports it as "referenced
## non-existent resource". Player-first lets that self-reference resolve via
## the normal (harmless) recursive-load path production code already takes.
const PlayerScene := preload("res://entities/player/player.tscn")
const MineScene := preload("res://entities/skills/scenes/cocoon_mine.tscn")


func _make_mine() -> CocoonMine:
	var mine: CocoonMine = MineScene.instantiate()
	add_child_autofree(mine)
	return mine


func _make_body(group: String) -> Node2D:
	var body := Node2D.new()
	body.add_to_group(group)
	add_child_autofree(body)
	var health := HealthComponent.new()
	health.current_health = health.max_health
	autofree(health)
	var hurtbox := Hurtbox.new()
	hurtbox.health = health
	hurtbox.name = "Hurtbox"
	body.add_child(hurtbox)
	return body


func test_body_entered_by_a_spider_deals_direct_damage_and_bursts_cosmetically() -> void:
	# Counts the delta, not an absolute total: another test in this file
	# (test_detonates_for_a_body_on_the_same_plane_it_was_armed_on) also
	# detonates and leaves its own MineSpiderling in the tree (spawned
	# inside CocoonMine._detonate(), not registered for autofree by either
	# test) — an absolute count would be order-dependent and flaky.
	var before_count := get_tree().get_nodes_in_group("mine_spiderlings").size()
	var mine := _make_mine()
	mine.arm(null, 3)
	var intruder := _make_body("spiders")

	mine._on_body_entered(intruder)

	var hurtbox := intruder.get_node("Hurtbox") as Hurtbox
	assert_eq(hurtbox.health.current_health, hurtbox.health.max_health - mine.burst_damage)
	assert_true(mine.is_queued_for_deletion(), "the mine consumes itself on detonation")
	assert_eq(get_tree().get_nodes_in_group("mine_spiderlings").size(), before_count + 3)


func test_ignores_a_larva_crossing_it() -> void:
	var mine := _make_mine()
	mine.arm(null, 2)
	var larva := _make_body("larvae")

	mine._on_body_entered(larva)

	assert_false(mine.is_queued_for_deletion(), "larvae are immune to Egg Mine")
	var hurtbox := larva.get_node("Hurtbox") as Hurtbox
	assert_eq(hurtbox.health.current_health, hurtbox.health.max_health)


func test_ignores_its_own_owner() -> void:
	var mine := _make_mine()
	var owner_spider := _make_body("spiders")
	mine.arm(owner_spider, 3)

	mine._on_body_entered(owner_spider)

	assert_false(mine.is_queued_for_deletion(), "the placer walking over their own mine doesn't trigger it")


func test_ignores_bodies_that_are_neither_a_spider_nor_a_larva() -> void:
	var mine := _make_mine()
	mine.arm(null, 3)
	var wall := StaticBody2D.new()
	add_child_autofree(wall)

	mine._on_body_entered(wall)

	assert_false(mine.is_queued_for_deletion())


func test_unarmed_mine_does_not_detonate() -> void:
	var mine := _make_mine()
	var intruder := _make_body("spiders")

	mine._on_body_entered(intruder) # never armed

	assert_false(mine.is_queued_for_deletion())


func test_ignores_a_body_on_a_different_plane_than_it_was_armed_on() -> void:
	var mine := _make_mine()
	mine.arm(null, 3, Level.Layer.CEILING)
	var ground_intruder := _make_body("spiders") # plain Node2D -> defaults to GROUND

	mine._on_body_entered(ground_intruder)

	assert_false(mine.is_queued_for_deletion(), "a ground-plane body doesn't trigger a ceiling-armed mine")


func test_detonates_for_a_body_on_the_same_plane_it_was_armed_on() -> void:
	var mine := _make_mine()
	mine.arm(null, 1, Level.Layer.CEILING)
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	player._plane.transition() # -> CEILING

	mine._on_body_entered(player)

	assert_true(mine.is_queued_for_deletion())


func test_joins_the_traps_group() -> void:
	var mine := _make_mine()
	assert_true(mine.is_in_group("traps"))
