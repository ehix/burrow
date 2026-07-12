extends GutTest
## Enemy's opportunistic melee against hatchlings (Hatchlings/VFX/input
## round): a hatchling within melee_range gets swatted regardless of
## Enemy's CHASE state/pathing — Enemy never targets hatchlings for pursuit
## (_acquire_target() only ever returns the player or a decoy), so without
## this a hatchling could never take damage in real play even though it now
## has a Hurtbox (see TinySpiderling). Doesn't touch _acquire_target(),
## _current_target, or the state machine/pathing at all.

const EnemyScene := preload("res://entities/enemy/enemy.tscn")
const SpiderlingScene := preload("res://entities/skills/scenes/tiny_spiderling.tscn")


func _make_enemy() -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.global_position = Vector2(500, 500)
	return enemy


func _make_hatchling(at: Vector2) -> TinySpiderling:
	var hatchling: TinySpiderling = SpiderlingScene.instantiate()
	add_child_autofree(hatchling)
	hatchling.global_position = at
	return hatchling


func test_melees_a_hatchling_within_range() -> void:
	var enemy := _make_enemy()
	var hatchling := _make_hatchling(enemy.global_position + Vector2(20, 0)) # within melee_range (56)

	enemy._melee_nearby_hatchling()

	assert_true(hatchling.is_queued_for_deletion(), "a hatchling within melee range gets swatted dead (1 HP)")


func test_ignores_a_hatchling_out_of_range() -> void:
	var enemy := _make_enemy()
	var hatchling := _make_hatchling(enemy.global_position + Vector2(500, 0)) # far beyond melee_range

	enemy._melee_nearby_hatchling()

	assert_false(hatchling.is_queued_for_deletion(), "a distant hatchling is never touched")


func test_respects_the_shared_melee_cooldown() -> void:
	var enemy := _make_enemy()
	var hatchling := _make_hatchling(enemy.global_position + Vector2(20, 0))
	enemy._melee_left = 1.0 # already on cooldown from another swing this frame

	enemy._melee_nearby_hatchling()

	assert_false(hatchling.is_queued_for_deletion(), "no swing while the shared melee cooldown is still active")


func test_does_not_touch_the_state_machine_or_current_target() -> void:
	var enemy := _make_enemy()
	_make_hatchling(enemy.global_position + Vector2(20, 0))
	var state_before := enemy.state
	var target_before := enemy._current_target

	enemy._melee_nearby_hatchling()

	assert_eq(enemy.state, state_before, "opportunistic hatchling melee never changes state")
	assert_eq(enemy._current_target, target_before, "opportunistic hatchling melee never sets _current_target")
