extends GutTest
## WorldItemPickup (item/inventory rework): a spider entering fills its
## InventoryComponent's single slot and consumes the pickup; a larva (or
## anything else) passes through untouched. Application/deployment now
## happens on InventoryComponent.use(), not on pickup — except for a spider
## whose InventoryComponent has auto_use = true (Enemy), which still applies
## immediately, matching the old walk-over-instant-consume behavior.

const PickupScene := preload("res://entities/items/world_item_pickup.tscn")


func _make_pickup(item: ConsumableItem = null) -> WorldItemPickup:
	var pickup: WorldItemPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	pickup.item = item
	return pickup


func _make_spider(auto_use: bool = false) -> Node2D:
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	add_child_autofree(spider)
	var status := StatusEffectComponent.new()
	spider.add_child(status)
	var inventory := InventoryComponent.new()
	inventory.auto_use = auto_use
	spider.add_child(inventory)
	return spider


func test_spider_entering_fills_its_inventory_and_frees_the_pickup() -> void:
	var item := FungusSenseItem.new()
	var pickup := _make_pickup(item)
	var spider := _make_spider()

	pickup._on_body_entered(spider)

	var inventory := spider.get_child(1) as InventoryComponent
	assert_eq(inventory.held_item, item)
	var status := spider.get_child(0) as StatusEffectComponent
	assert_false(status.has(&"sense"), "not applied yet -- only picked up")
	assert_true(pickup.is_queued_for_deletion())


func test_auto_use_spider_applies_the_item_immediately_on_pickup() -> void:
	var pickup := _make_pickup(FungusSenseItem.new())
	var spider := _make_spider(true)

	pickup._on_body_entered(spider)

	var status := spider.get_child(0) as StatusEffectComponent
	assert_true(status.has(&"sense"))
	assert_true(pickup.is_queued_for_deletion())


func test_refuses_pickup_when_the_spiders_slot_is_already_full() -> void:
	var spider := _make_spider()
	var inventory := spider.get_child(1) as InventoryComponent
	var first := SeedPodItem.new()
	inventory.try_pickup(first, spider)
	var pickup := _make_pickup(FungusSenseItem.new())

	pickup._on_body_entered(spider)

	assert_false(pickup.is_queued_for_deletion(), "second item stays in the world")
	assert_eq(inventory.held_item, first, "the first held item is untouched")


func test_ignores_bodies_that_are_not_spiders() -> void:
	var pickup := _make_pickup(FungusSenseItem.new())
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	add_child_autofree(larva)

	pickup._on_body_entered(larva)

	assert_false(pickup.is_queued_for_deletion())


func test_without_an_item_assigned_is_a_noop() -> void:
	var pickup := _make_pickup(null)
	var spider := _make_spider()

	pickup._on_body_entered(spider) # must not error

	assert_false(pickup.is_queued_for_deletion())
