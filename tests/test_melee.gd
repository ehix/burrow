extends GutTest
## Player melee: kills a larva outright in range (mirrors a web shot), only
## costs hunger on a landed hit (never on a whiff), and — once the swinger is
## already starving — a landed hit drains health instead via charge_all's
## fail-safe.

const PlayerScene := preload("res://entities/player/player.tscn")
const LarvaScene := preload("res://entities/larva/larva.tscn")


func _make_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	add_child_autofree(player)
	player.global_position = Vector2(500, 500)
	player.facing = Vector2.RIGHT
	return player


func _make_larva_at(world_position: Vector2) -> Larva:
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)
	larva.global_position = world_position
	return larva


func test_melee_kills_a_larva_in_range() -> void:
	var player := _make_player()
	var larva := _make_larva_at(Vector2(548, 500)) # one tile ahead
	assert_true(larva.is_in_group("larvae"))
	player._melee()
	assert_false(larva.is_in_group("larvae"), "a melee-killed larva is no longer edible")


func test_melee_out_of_range_does_not_kill_the_larva() -> void:
	var player := _make_player()
	var larva := _make_larva_at(Vector2(900, 900)) # far away
	player._melee()
	assert_true(larva.is_in_group("larvae"), "an out-of-range larva is untouched")


func test_melee_hit_costs_hunger() -> void:
	var player := _make_player()
	_make_larva_at(Vector2(548, 500)) # in range: the swing lands
	var before := player.hunger.current_hunger
	player._melee()
	assert_almost_eq(player.hunger.current_hunger, before + player.melee_hunger_cost, 0.001,
		"a landed hit costs hunger")


func test_melee_whiff_costs_no_hunger() -> void:
	var player := _make_player() # nothing in range: the swing whiffs
	var before := player.hunger.current_hunger
	player._melee()
	assert_eq(player.hunger.current_hunger, before, "a whiff never costs hunger")


func test_melee_drains_health_instead_of_hunger_once_starving() -> void:
	var player := _make_player()
	_make_larva_at(Vector2(548, 500)) # in range, so the swing lands
	player.hunger.current_hunger = player.hunger.max_hunger # already starving
	var health_before := player.health.current_health
	player._melee()
	assert_eq(player.hunger.current_hunger, player.hunger.max_hunger, "hunger stays capped")
	assert_almost_eq(player.health.current_health, health_before - player.melee_hunger_cost, 0.001,
		"a landed hit's cost drains health instead of hunger once maxed")


func test_melee_hits_a_blockade_in_range() -> void:
	var player := _make_player()
	var blockade := Blockade.new()
	add_child_autofree(blockade)
	blockade.setup(3)
	blockade.global_position = Vector2(548, 500) # one tile ahead
	player._melee()
	assert_eq(blockade._hits, 1, "the swing landed one hit on the blockade")


func test_melee_costs_hunger_when_it_lands_on_a_blockade() -> void:
	var player := _make_player()
	var blockade := Blockade.new()
	add_child_autofree(blockade)
	blockade.setup(3)
	blockade.global_position = Vector2(548, 500)
	var before := player.hunger.current_hunger
	player._melee()
	assert_almost_eq(player.hunger.current_hunger, before + player.melee_hunger_cost, 0.001,
		"a landed hit on a blockade costs hunger like any other landed melee hit")


func test_melee_hits_only_the_intended_blockade_not_an_adjacent_one() -> void:
	# Playtest bug: with two blockades on adjacent tiles, meleeing the near
	# one could instead land on the far one — melee_range (60px) also covers
	# an orthogonally-adjacent tile (48px away), so the old distance-based
	# check matched both and picked whichever the group enumerated first.
	# far_blockade is created first so it enumerates first, reproducing the
	# bug against the old code (the actual placement order in the reported
	# scenario doesn't matter — this just forces the ambiguous case).
	var player := _make_player()
	var far_blockade := Blockade.new()
	add_child_autofree(far_blockade)
	far_blockade.setup(3)
	far_blockade.global_position = Vector2(596, 500) # two tiles ahead
	var near_blockade := Blockade.new()
	add_child_autofree(near_blockade)
	near_blockade.setup(3)
	near_blockade.global_position = Vector2(548, 500) # one tile ahead — the actual target

	player._melee()

	assert_eq(near_blockade._hits, 1, "the intended, targeted blockade takes the hit")
	assert_eq(far_blockade._hits, 0, "an adjacent blockade one tile further is untouched")


func test_melee_always_spawns_the_slash_regardless_of_hit() -> void:
	var player := _make_player() # nothing in range: a whiff
	var holder := Node2D.new()
	add_child_autofree(holder)
	player.reparent(holder)
	var children_before := holder.get_child_count()
	player._melee()
	assert_gt(holder.get_child_count(), children_before, "the slash VFX spawns even on a whiff")
