extends GutTest
## StatusEffectComponent: the unified tick-based buff/debuff timer (design
## guardrail — re-applying an id refreshes it instead of stacking a second
## competing timer for the same slot).


func _make() -> StatusEffectComponent:
	var status := StatusEffectComponent.new()
	autofree(status)
	return status


func test_apply_then_has_and_magnitude() -> void:
	var status := _make()
	status.apply(&"poison", 3.0, 5.0)
	assert_true(status.has(&"poison"))
	assert_eq(status.magnitude(&"poison"), 3.0)


func test_missing_effect_reads_as_absent_with_zero_magnitude() -> void:
	var status := _make()
	assert_false(status.has(&"poison"))
	assert_eq(status.magnitude(&"poison"), 0.0)


func test_tick_counts_down_and_expires() -> void:
	var status := _make()
	status.apply(&"poison", 3.0, 1.0)
	status.tick(0.6)
	assert_true(status.has(&"poison"))
	status.tick(0.5)
	assert_false(status.has(&"poison"), "expires once time_left drops to/below zero")


func test_reapplying_the_same_id_refreshes_instead_of_stacking() -> void:
	var status := _make()
	status.apply(&"poison", 3.0, 1.0)
	status.tick(0.9) # nearly expired
	status.apply(&"poison", 5.0, 1.0) # refreshed — a re-apply, not a second timer
	assert_eq(status.magnitude(&"poison"), 5.0)
	status.tick(0.9)
	assert_true(status.has(&"poison"), "the refresh reset the full duration")


func test_on_tick_callback_runs_each_tick() -> void:
	var status := _make()
	var total := {"value": 0.0}
	status.apply(&"poison", 2.0, 1.0,
		func(delta: float, magnitude: float) -> void: total["value"] += magnitude * delta)
	status.tick(0.5)
	assert_eq(total["value"], 1.0)


func test_on_expire_callback_runs_once_on_expiry() -> void:
	var status := _make()
	var expired := {"count": 0}
	status.apply(&"poison", 1.0, 0.5, Callable(),
		func() -> void: expired["count"] += 1)
	status.tick(0.6)
	assert_eq(expired["count"], 1)
	status.tick(0.1)
	assert_eq(expired["count"], 1, "does not fire again once already expired/erased")


func test_copy_active_into_preserves_remaining_time() -> void:
	var from_status := _make()
	var to_status := _make()
	from_status.apply(&"poison", 4.0, 1.0)
	from_status.tick(0.4)
	from_status.copy_active_into(to_status)
	assert_true(to_status.has(&"poison"))
	assert_eq(to_status.magnitude(&"poison"), 4.0)
	assert_almost_eq(to_status.time_left(&"poison"), 0.6, 0.001)
