extends GutTest
## StatusEffectRow (UI/HUD overhaul): one badge per active status-effect id
## for whichever spider this row is bound to, ignoring effects on any other
## spider. Countdown ticks locally toward zero; removal happens on
## EventBus.status_effect_expired.

const StatusEffectRowScene := preload("res://ui/status_effect_row.tscn")


func _make_row() -> StatusEffectRow:
	var row: StatusEffectRow = StatusEffectRowScene.instantiate()
	add_child_autofree(row)
	return row


func _make_spider() -> Node2D:
	var spider := Node2D.new()
	add_child_autofree(spider)
	return spider


func test_shows_a_badge_when_its_bound_spider_gets_a_status_effect() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)

	row._on_status_effect_applied(spider, &"poison", 2.0, 3.0)

	assert_true(row._badges.has(&"poison"))
	assert_eq(row._badges[&"poison"].text, "Poisoned 3")


func test_ignores_a_status_effect_on_a_different_spider() -> void:
	var row := _make_row()
	var spider := _make_spider()
	var other := _make_spider()
	row.bind_spider(spider)

	row._on_status_effect_applied(other, &"poison", 2.0, 3.0)

	assert_false(row._badges.has(&"poison"))


func test_badge_counts_down_over_time() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)
	row._on_status_effect_applied(spider, &"sense", 1.0, 5.0)

	row._process(2.0)

	assert_eq(row._badges[&"sense"].text, "Sense 3")


func test_badge_removed_on_status_effect_expired() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)
	row._on_status_effect_applied(spider, &"sense", 1.0, 5.0)

	row._on_status_effect_expired(spider, &"sense")

	assert_false(row._badges.has(&"sense"))


func test_unknown_status_id_falls_back_to_its_raw_name() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)

	row._on_status_effect_applied(spider, &"mystery_buff", 1.0, 4.0)

	assert_eq(row._badges[&"mystery_buff"].text, "mystery_buff 4")


func test_real_event_bus_emission_reaches_the_bound_spider() -> void:
	var row := _make_row()
	var spider := _make_spider()
	row.bind_spider(spider)

	EventBus.status_effect_applied.emit(spider, &"poison", 2.0, 3.0)

	assert_true(row._badges.has(&"poison"))


func test_rebinding_to_a_new_spider_clears_stale_badges_from_the_old_one() -> void:
	var row := _make_row()
	var spider_a := _make_spider()
	var spider_b := _make_spider()
	row.bind_spider(spider_a)
	row._on_status_effect_applied(spider_a, &"poison", 2.0, 3.0)

	row.bind_spider(spider_b)

	assert_eq(row._badges.size(), 0)
	assert_false(row._badges.has(&"poison"))
