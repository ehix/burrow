extends GutTest
## LurePulse (design §5): active the instant it's placed (never picked up),
## pulls nearby larvae toward itself each pulse, and disappears after
## item.duration.

const LurePulseScene := preload("res://entities/items/lure_pulse.tscn")
const LarvaScene := preload("res://entities/larva/larva.tscn")


func _make_lure(duration: float = 8.0, radius: float = 200.0) -> LurePulse:
	var lure: LurePulse = LurePulseScene.instantiate()
	var item := LureItem.new()
	item.duration = duration
	item.pulse_radius = radius
	lure.item = item
	add_child_autofree(lure)
	return lure


func test_expires_after_its_duration() -> void:
	var lure := _make_lure(1.0)
	lure._physics_process(0.6)
	assert_false(lure.is_queued_for_deletion())
	lure._physics_process(0.5)
	assert_true(lure.is_queued_for_deletion())


func test_without_an_item_frees_immediately() -> void:
	var lure: LurePulse = LurePulseScene.instantiate()
	add_child_autofree(lure)
	lure._physics_process(0.016)
	assert_true(lure.is_queued_for_deletion())


func test_pulse_nudges_a_nearby_larva_closer() -> void:
	var lure := _make_lure()
	lure.global_position = Vector2(1000, 1000)
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)
	larva.global_position = Vector2(1000, 1096) # two tiles below, within pulse_radius
	var before := larva.global_position.distance_to(lure.global_position)

	lure._pulse()
	# The nudge starts a GridMover step animation rather than teleporting —
	# tick it to completion to observe the result.
	for i in 10:
		larva._mover.tick(0.05)

	assert_lt(larva.global_position.distance_to(lure.global_position), before,
		"the larva stepped toward the lure")


func test_pulse_ignores_larvae_outside_the_radius() -> void:
	var lure := _make_lure(8.0, 50.0) # small radius
	lure.global_position = Vector2(0, 0)
	var larva: Larva = LarvaScene.instantiate()
	add_child_autofree(larva)
	larva.global_position = Vector2(2000, 2000) # far outside
	var before := larva.global_position

	lure._pulse()
	for i in 10:
		larva._mover.tick(0.05)

	assert_eq(larva.global_position, before, "a larva outside pulse_radius is untouched")
