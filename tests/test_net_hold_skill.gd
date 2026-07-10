extends GutTest
## NetHoldSkill's contract (Net-caster rework, playtest correction): pick up
## any unspent trap within reach — laid by anyone, ownership doesn't gate
## pickup — and hold it out ahead of your facing tile; a larva that touches
## that forward tile is eaten and the trap is spent; a trap that already held
## a larva is auto-eaten on pickup instead. No manual drop. activate() itself
## (not just _on_activate()) must gate on trap-availability and on already
## holding, so continuously holding the input down never burns cooldown/
## hunger on an idle frame.

class FakeSpider:
	extends Node2D
	var facing := Vector2.RIGHT


class FakeCaughtLarva:
	extends Node2D
	var caught := true


func _make_spider(hunger_value: float = 50.0) -> Array:
	var spider := FakeSpider.new()
	add_child_autofree(spider)
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.current_hunger = hunger_value
	spider.add_child(hunger)
	return [spider, hunger]


func _make_trap(owner_spider: Node) -> WebTrap:
	var trap := WebTrap.new()
	trap.setup(owner_spider)
	add_child_autofree(trap)
	return trap


func _make_larva() -> Node2D:
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	add_child_autofree(larva)
	return larva


func test_pickup_succeeds_regardless_of_trap_owner() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var other := Node2D.new()
	autofree(other)
	var trap := _make_trap(other) # laid by someone else entirely
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)

	assert_true(skill.holding, "any trap on the map is eligible, not just ones you placed")
	assert_true(trap.is_queued_for_deletion())


func test_pickup_a_trap_within_reach() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)

	assert_true(skill.holding)
	assert_true(trap.is_queued_for_deletion(), "the placed trap is picked up, not left standing")


func test_pickup_ignores_a_trap_out_of_reach() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position + Vector2(500, 0)

	var skill := NetHoldSkill.new()
	skill.reach = 48.0
	add_child_autofree(skill)
	skill._on_activate(spider)

	assert_false(skill.holding)


func test_picking_up_a_preloaded_trap_eats_the_larva_immediately() -> void:
	var pair := _make_spider(50.0)
	var spider: Node2D = pair[0]
	var hunger: HungerComponent = pair[1]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position
	trap.catch_larva(_make_larva())

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)

	assert_true(skill.holding, "you're still holding the now-empty trap")
	assert_almost_eq(hunger.current_hunger, 10.0, 0.001, "the preloaded larva is eaten on pickup")


func test_a_larva_touching_the_held_forward_tile_is_eaten_and_the_trap_is_spent() -> void:
	var pair := _make_spider(50.0)
	var spider: Node2D = pair[0]
	var hunger: HungerComponent = pair[1]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)
	assert_true(skill.holding)

	var larva := _make_larva()
	larva.global_position = spider.global_position + Vector2.RIGHT * 48.0 # one tile ahead, facing RIGHT

	skill._physics_process(0.016)

	assert_false(skill.holding, "the trap is spent once it catches a larva")
	assert_almost_eq(hunger.current_hunger, 10.0, 0.001)


func test_a_larva_far_from_the_forward_tile_is_left_alone() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)

	var larva := _make_larva()
	larva.global_position = spider.global_position + Vector2(500, 500)

	skill._physics_process(0.016)

	assert_true(skill.holding, "a distant larva doesn't trigger the catch")


func test_spend_ends_holding_without_eating_anything() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)
	assert_true(skill.holding)

	skill.spend()

	assert_false(skill.holding)


func test_cannot_pick_up_a_second_trap_while_already_holding() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var first_trap := _make_trap(spider)
	first_trap.global_position = spider.global_position
	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)
	assert_true(skill.holding)

	var second_trap := _make_trap(spider)
	second_trap.global_position = spider.global_position
	skill._on_activate(spider)

	assert_false(second_trap.is_queued_for_deletion(), "already holding — the second trap stays on the ground")


func test_a_larva_already_caught_elsewhere_is_left_alone_by_the_forward_tile_scan() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	skill._on_activate(spider)
	assert_true(skill.holding)

	var larva := FakeCaughtLarva.new()
	larva.add_to_group("larvae")
	add_child_autofree(larva)
	larva.global_position = spider.global_position + Vector2.RIGHT * 48.0

	skill._physics_process(0.016)

	assert_true(skill.holding, "an already-caught larva is not stolen by this held trap")


func test_activate_returns_false_and_charges_nothing_when_no_trap_in_reach() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)

	var fired := skill.activate(spider)

	assert_false(fired, "nothing to pick up")
	assert_true(skill.can_activate(), "no cooldown/hunger spent on a no-op — safe to hold the input down")


func test_activate_stays_a_noop_while_holding_even_after_cooldown_expires() -> void:
	var pair := _make_spider()
	var spider: Node2D = pair[0]
	var trap := _make_trap(spider)
	trap.global_position = spider.global_position

	var skill := NetHoldSkill.new()
	add_child_autofree(skill)
	assert_true(skill.activate(spider))
	assert_true(skill.holding)
	skill._cooldown_left = 0.0 # simulate cooldown having fully expired

	var second_trap := _make_trap(spider)
	second_trap.global_position = spider.global_position

	var fired_again := skill.activate(spider)

	assert_false(fired_again, "still holding — activate() is a no-op regardless of cooldown")
	assert_false(second_trap.is_queued_for_deletion(), "second trap untouched while still holding the first")
