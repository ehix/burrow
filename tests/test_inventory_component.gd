extends GutTest
## InventoryComponent (item/inventory rework): single-slot carry. `use()`
## applies a consumable or, for a held Lure, deploys a LurePulse instead.
## `auto_use = true` (Enemy) makes try_pickup() call use() immediately,
## reproducing the old walk-over-instant-consume behavior through the same
## component Player uses.


func _make_inventory(auto_use: bool = false) -> InventoryComponent:
	var spider := Node2D.new()
	add_child_autofree(spider)
	var inventory := InventoryComponent.new()
	inventory.auto_use = auto_use
	spider.add_child(inventory)
	return inventory


func _make_consumer_with_status() -> Node2D:
	var consumer := Node2D.new()
	add_child_autofree(consumer)
	var status := StatusEffectComponent.new()
	consumer.add_child(status)
	return consumer


func test_try_pickup_fills_an_empty_slot() -> void:
	var inventory := _make_inventory()
	var item := FungusSenseItem.new()

	var picked_up := inventory.try_pickup(item, Node2D.new())

	assert_true(picked_up)
	assert_eq(inventory.held_item, item)


func test_try_pickup_refuses_when_the_slot_is_occupied() -> void:
	var inventory := _make_inventory()
	var first := FungusSenseItem.new()
	inventory.try_pickup(first, Node2D.new())

	var picked_up := inventory.try_pickup(SeedPodItem.new(), Node2D.new())

	assert_false(picked_up)
	assert_eq(inventory.held_item, first, "the second item is refused, first stays held")


func test_try_pickup_emits_item_held_changed() -> void:
	var inventory := _make_inventory()
	var item := SeedPodItem.new()
	var received: Array = []
	inventory.item_held_changed.connect(func(held: ConsumableItem) -> void: received.append(held))

	inventory.try_pickup(item, Node2D.new())

	assert_eq(received, [item])


func test_use_applies_a_consumable_and_clears_the_slot() -> void:
	var inventory := _make_inventory()
	var consumer := _make_consumer_with_status()
	inventory.try_pickup(FungusSenseItem.new(), consumer)

	inventory.use(consumer)

	var status := consumer.get_child(0) as StatusEffectComponent
	assert_true(status.has(&"sense"))
	assert_null(inventory.held_item)


func test_use_emits_item_held_changed_with_null() -> void:
	var inventory := _make_inventory()
	var consumer := _make_consumer_with_status()
	inventory.try_pickup(FungusSenseItem.new(), consumer)
	var received: Array = []
	inventory.item_held_changed.connect(func(held: ConsumableItem) -> void: received.append(held))

	inventory.use(consumer)

	assert_eq(received, [null])


func test_use_on_an_empty_slot_is_a_noop() -> void:
	var inventory := _make_inventory()
	var consumer := _make_consumer_with_status()

	inventory.use(consumer) # must not error

	assert_null(inventory.held_item)


func test_use_on_a_held_lure_spawns_a_lure_pulse_with_its_duration() -> void:
	var inventory := _make_inventory()
	var consumer := Node2D.new()
	add_child_autofree(consumer)
	consumer.global_position = Vector2(300, 300)
	inventory.try_pickup(LureItem.new(), consumer)

	inventory.use(consumer)

	assert_null(inventory.held_item)
	var pulses := get_tree().get_nodes_in_group("world_items")
	assert_eq(pulses.size(), 1)
	var pulse := pulses[0] as LurePulse
	assert_eq(pulse.item.duration, 60.0)
	assert_eq(pulse.global_position, consumer.global_position)


func test_auto_use_consumes_immediately_on_pickup() -> void:
	var inventory := _make_inventory(true)
	var consumer := _make_consumer_with_status()

	inventory.try_pickup(FungusSenseItem.new(), consumer)

	var status := consumer.get_child(0) as StatusEffectComponent
	assert_true(status.has(&"sense"))
	assert_null(inventory.held_item, "auto_use clears the slot the same frame it fills")
