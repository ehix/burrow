extends GutTest
## Enemy's opportunistic melee against a Centipede (sub-project H): mirrors
## _melee_nearby_hatchling() in spirit (an "opportunistic swing that isn't
## Enemy's tracked CHASE target") but uses an exact-tile lookup instead of a
## distance threshold, since Centipede.segment_at_tile() -- like
## Blockade.at_tile(), which Player._melee() already uses the same way --
## isn't a Hurtbox-bearing target _melee_target() can reach.

const EnemyScene := preload("res://entities/enemy/enemy.tscn")


func _make_enemy() -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(500, 500)
	return enemy


func _make_level() -> Level:
	var level: Level = preload("res://world/level.tscn").instantiate()
	add_child_autofree(level)
	level.build()
	# This file places its own centipede(s) at tiles it controls directly --
	# free any centipede Level.build() auto-seeded (Task 8) so it can never
	# collide with (or be found instead of) the tiles these tests place.
	# (Unlike Player._melee(), the enemy._melee_nearby_centipede() these
	# tests call directly has no "spiders" group scan ahead of its Centipede
	# check, so Level's own internally-spawned player/enemy can't intercept
	# it the way test_melee.gd's centipede tests could -- no fix needed
	# there.)
	for node in get_tree().get_nodes_in_group("centipedes"):
		node.free()
	return level


func _make_centipede_at(level: Level, tile: Vector2i) -> Centipede:
	var centipede := Centipede.new()
	add_child_autofree(centipede)
	centipede.bind_level(level)
	centipede.spawn_at([tile])
	return centipede


func test_melees_a_centipede_on_the_tile_ahead() -> void:
	var enemy := _make_enemy()
	var level := _make_level()
	var target_tile: Vector2i = enemy._mover.committed_tile() + Vector2i(int(enemy.facing.x), int(enemy.facing.y))
	var centipede := _make_centipede_at(level, target_tile)

	enemy._melee_nearby_centipede()

	assert_eq(centipede._hits, 1, "the swing landed one hit on the centipede ahead")


func test_ignores_a_centipede_not_on_the_tile_ahead() -> void:
	var enemy := _make_enemy()
	var level := _make_level()
	var far_tile: Vector2i = enemy._mover.committed_tile() + Vector2i(5, 5)
	var centipede := _make_centipede_at(level, far_tile)

	enemy._melee_nearby_centipede()

	assert_eq(centipede._hits, 0, "a centipede not on the exact tile ahead is untouched")


func test_respects_the_shared_melee_cooldown() -> void:
	var enemy := _make_enemy()
	var level := _make_level()
	var target_tile: Vector2i = enemy._mover.committed_tile() + Vector2i(int(enemy.facing.x), int(enemy.facing.y))
	var centipede := _make_centipede_at(level, target_tile)
	enemy._melee_left = 1.0 # already on cooldown from another swing this frame

	enemy._melee_nearby_centipede()

	assert_eq(centipede._hits, 0, "no swing while the shared melee cooldown is still active")
