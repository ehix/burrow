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
	var health := HealthComponent.new()
	health.max_health = 100.0
	health.current_health = 100.0
	spider.add_child(health)
	autofree(spider)
	return [spider, hunger, health]


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


func test_consuming_a_larva_never_damages_the_spider() -> void:
	var trap := _make_trap()
	var pair := _make_spider(50.0)
	trap.catch_larva(_make_larva())
	trap.try_consume(pair[0])
	assert_eq((pair[2] as HealthComponent).current_health, 100.0,
		"harvesting a caught larva must never cost health")


## A minimal double recording apply_web_hit calls, since the fake spiders
## above are plain Node2Ds without Player/Enemy's real reaction method.
class RecordingSpider:
	extends Node2D
	var hits: Array = []
	func apply_web_hit(push_dir: Vector2i, factor: float, slow_duration: float, stun_duration: float) -> void:
		hits.append([push_dir, factor, slow_duration, stun_duration])


func test_entangle_slows_the_placer_too_no_owner_immunity() -> void:
	var trap := _make_trap()
	trap.web_slow_factor = 0.5
	trap.web_slow_duration = 1.5
	trap._entangle_armed = true # past the placement grace period
	var owner := RecordingSpider.new()
	autofree(owner)
	trap.setup(owner)
	trap._entangle(owner) # the placer crossing their own web
	assert_eq(owner.hits.size(), 1, "the placer is entangled by their own web")
	assert_eq(owner.hits[0][1], 0.5, "50% slow factor")
	assert_eq(owner.hits[0][2], 1.5, "slow duration applied")
	assert_eq(owner.hits[0][3], 0.0, "no stun from a web crossing")


## Regression: a trap spawns at the placer's own position, so its CatchArea
## sees their already-standing body as a "new" overlap the instant it's
## created — without a grace period the placer got entangled the moment they
## placed the trap, before crossing anything. If a larva is then caught and
## eaten a second later, the trap is gone but that earlier slow keeps running.
func test_entangle_is_a_noop_during_the_placement_grace_period() -> void:
	var trap := _make_trap()
	var spider := RecordingSpider.new()
	autofree(spider)
	trap.setup(spider)
	trap._entangle(spider) # fresh trap: _entangle_armed defaults to false
	assert_eq(spider.hits.size(), 0, "no entangle in the instant after placement")


func test_entangle_works_normally_once_armed() -> void:
	var trap := _make_trap()
	trap._entangle_armed = true
	var spider := RecordingSpider.new()
	autofree(spider)
	trap._entangle(spider)
	assert_eq(spider.hits.size(), 1, "entangle works normally once the grace period has passed")


func test_catch_and_consume_are_unaffected_by_the_grace_period() -> void:
	# Catching/eating a larva must work immediately, even during the grace
	# period — only the entangle slow is gated, nothing else.
	var trap := _make_trap()
	var pair := _make_spider(50.0)
	trap.catch_larva(_make_larva())
	trap.try_consume(pair[0])
	assert_true(trap.spent, "consuming a larva is unaffected by the entangle grace period")


func test_tile_has_caught_web_true_when_a_trap_holds_a_larva() -> void:
	var trap := _make_trap()
	trap.global_position = Vector2(240, 240) # tile (5,5)
	trap.catch_larva(_make_larva())
	assert_true(WebTrap.tile_has_caught_web(get_tree(), Vector2i(5, 5), 48))


func test_tile_has_caught_web_false_when_the_web_is_empty() -> void:
	var trap := _make_trap()
	trap.global_position = Vector2(240, 240) # tile (5,5)
	assert_false(WebTrap.tile_has_caught_web(get_tree(), Vector2i(5, 5), 48),
		"an empty web is not a boundary — only an occupied one is")


func test_tile_has_caught_web_false_at_a_different_tile() -> void:
	var trap := _make_trap()
	trap.global_position = Vector2(240, 240) # tile (5,5)
	trap.catch_larva(_make_larva())
	assert_false(WebTrap.tile_has_caught_web(get_tree(), Vector2i(9, 9), 48))


func test_body_entered_skips_entangle_when_a_spider_eats_the_caught_larva() -> void:
	var trap := _make_trap()
	trap.catch_larva(_make_larva())
	var spider := RecordingSpider.new()
	spider.add_to_group("spiders")
	var hunger := HungerComponent.new()
	hunger.max_hunger = 100.0
	hunger.current_hunger = 50.0
	spider.add_child(hunger)
	autofree(spider)
	trap._on_body_entered(spider)
	assert_eq(spider.hits.size(), 0, "eating a caught larva must not also entangle you")
	assert_true(trap.spent, "the larva was consumed")
	assert_almost_eq(hunger.current_hunger, 10.0, 0.001)


func test_body_entered_still_entangles_when_the_web_is_empty() -> void:
	var trap := _make_trap()
	trap._entangle_armed = true # past the placement grace period
	var spider := RecordingSpider.new()
	spider.add_to_group("spiders")
	autofree(spider)
	trap._on_body_entered(spider) # nothing caught: just crossing the web
	assert_eq(spider.hits.size(), 1, "crossing an empty web still entangles")
