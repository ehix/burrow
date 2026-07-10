extends GutTest
## The debug indicator overlay lights up a held/state-flag entry while its
## check is true, and flashes a one-shot entry for a moment after it fires.

const IndicatorsScene := preload("res://ui/control_indicators.tscn")


func after_each() -> void:
	GameState.noclip = false # don't leak into other tests
	GameState.playtest_mode = false


func _make() -> ControlIndicators:
	var indicators: ControlIndicators = IndicatorsScene.instantiate()
	add_child_autofree(indicators)
	return indicators


func _entry_for(indicators: ControlIndicators, text: String) -> ControlIndicators.Entry:
	for entry in indicators._entries:
		if entry.label.text == text:
			return entry
	return null


func test_builds_one_entry_per_tracked_action() -> void:
	var indicators := _make()
	assert_eq(indicators._entries.size(), 26 + UpgradeRegistry.ALL.size())


func test_held_entry_lights_up_while_its_check_is_true() -> void:
	var indicators := _make()
	var entry := _entry_for(indicators, "Noclip (K)")
	assert_not_null(entry)

	GameState.noclip = true
	indicators._process(0.016)
	assert_eq(entry.label.modulate, ControlIndicators.ACTIVE_COLOR)

	GameState.noclip = false
	indicators._process(0.016)
	assert_eq(entry.label.modulate, ControlIndicators.IDLE_COLOR)


func test_playtest_mode_entry_lights_up_while_active() -> void:
	var indicators := _make()
	var entry := _entry_for(indicators, "Playtest Mode (0)")
	assert_not_null(entry)

	GameState.playtest_mode = true
	indicators._process(0.016)
	assert_eq(entry.label.modulate, ControlIndicators.ACTIVE_COLOR)

	GameState.playtest_mode = false
	indicators._process(0.016)
	assert_eq(entry.label.modulate, ControlIndicators.IDLE_COLOR)


func test_one_shot_entry_flashes_then_fades() -> void:
	# A synthetic entry with a controllable check, rather than the real
	# "melee" action: Input.is_action_just_pressed() only clears on a real
	# engine frame boundary, which two synchronous _process() calls in a test
	# never cross, so driving it through actual Input would be flaky.
	# `fired` is a 1-element array (not a plain bool) because GDScript lambdas
	# capture locals by value at creation time — a later reassignment of a
	# plain bool wouldn't be seen by the already-created Callable, but the
	# array reference itself is shared and its contents are mutable.
	var indicators := _make()
	var fired := [true]
	var entry := ControlIndicators.Entry.new()
	entry.label = Label.new()
	entry.is_one_shot = true
	entry.check = func() -> bool: return fired[0]
	indicators.add_child(entry.label)
	indicators._entries.append(entry)

	indicators._process(0.016)
	assert_eq(entry.label.modulate, ControlIndicators.ACTIVE_COLOR, "flashes the instant it fires")

	fired[0] = false
	entry.flash_until = 0.0 # simulate the flash window having elapsed
	indicators._process(0.016)
	assert_eq(entry.label.modulate, ControlIndicators.IDLE_COLOR, "fades back once the flash ends")
