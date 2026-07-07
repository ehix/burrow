extends GutTest
## Trap catch/consume resolution (design §9): larva vs. spider, ownership,
## spend-on-consume. Drives the public methods directly so no physics frames
## are needed.


func _make_spider(hunger_value: float) -> Array:
	# Returns [spider_node, hunger_component]. Kept out of the SceneTree so the
	# hunger component doesn't tick during the test.
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.current_hunger = hunger_value
	spider.add_child(hunger)
	autofree(spider)
	return [spider, hunger]


func _make_trap() -> WebTrap:
	var trap := WebTrap.new()
	trap.satiation = 40.0
	add_child_autofree(trap)
	return trap


func _make_larva() -> Node2D:
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	autofree(larva)
	return larva


func test_catch_holds_the_larva() -> void:
	var trap := _make_trap()
	var larva := _make_larva()
	watch_signals(EventBus)
	trap.catch_larva(larva)
	assert_eq(trap.caught_larva, larva)
	assert_signal_emitted(EventBus, "larva_trapped")


func test_consume_satiates_and_spends_trap() -> void:
	var trap := _make_trap()
	var pair := _make_spider(50.0)
	trap.catch_larva(_make_larva())
	watch_signals(EventBus)
	trap.try_consume(pair[0])
	assert_true(trap.spent, "trap is spent on consumption")
	assert_almost_eq((pair[1] as HungerComponent).current_hunger, 10.0, 0.001)
	assert_signal_emitted(EventBus, "larva_consumed")


func test_consume_empty_trap_is_noop() -> void:
	var trap := _make_trap()
	var pair := _make_spider(50.0)
	trap.try_consume(pair[0])
	assert_false(trap.spent)
	assert_eq((pair[1] as HungerComponent).current_hunger, 50.0)


func test_any_spider_can_consume_regardless_of_owner() -> void:
	var trap := _make_trap()
	var owner_pair := _make_spider(50.0)
	var other_pair := _make_spider(80.0)
	trap.setup(owner_pair[0]) # owned by the first spider...
	trap.catch_larva(_make_larva())
	trap.try_consume(other_pair[0]) # ...consumed by the second
	assert_true(trap.spent)
	assert_almost_eq((other_pair[1] as HungerComponent).current_hunger, 40.0, 0.001)


func test_spent_trap_cannot_be_consumed_twice() -> void:
	var trap := _make_trap()
	var first := _make_spider(50.0)
	var second := _make_spider(90.0)
	trap.catch_larva(_make_larva())
	trap.try_consume(first[0])
	trap.try_consume(second[0]) # already spent
	assert_almost_eq((second[1] as HungerComponent).current_hunger, 90.0, 0.001,
		"second spider gets nothing from a spent trap")


func test_third_web_hit_destroys_the_trap() -> void:
	var trap := _make_trap()
	trap.take_web_hit()
	trap.take_web_hit()
	assert_false(trap.spent, "two hits do not destroy the trap")
	trap.take_web_hit()
	assert_true(trap.spent, "the third hit destroys the trap")


func test_web_hits_ignored_once_spent() -> void:
	var trap := _make_trap()
	var pair := _make_spider(50.0)
	trap.catch_larva(_make_larva())
	trap.try_consume(pair[0]) # spent via consumption
	trap.take_web_hit() # must be a no-op, not error
	assert_true(trap.spent)
