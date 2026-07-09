extends GutTest
## WorldItemPickup (design §5): a spider entering triggers item.apply() and
## consumes the pickup; a larva (or anything else) passes through untouched.

const PickupScene := preload("res://entities/items/world_item_pickup.tscn")


func _make_pickup(item: ConsumableItem = null) -> WorldItemPickup:
	var pickup: WorldItemPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	pickup.item = item
	return pickup


func _make_spider_with_status() -> Node2D:
	var spider := Node2D.new()
	spider.add_to_group("spiders")
	add_child_autofree(spider)
	var status := StatusEffectComponent.new()
	spider.add_child(status)
	return spider


func test_spider_entering_applies_the_item_and_frees_the_pickup() -> void:
	var pickup := _make_pickup(FungusSenseItem.new())
	var spider := _make_spider_with_status()

	pickup._on_body_entered(spider)

	var status := spider.get_child(0) as StatusEffectComponent
	assert_true(status.has(&"sense"))
	assert_true(pickup.is_queued_for_deletion())


func test_ignores_bodies_that_are_not_spiders() -> void:
	var pickup := _make_pickup(FungusSenseItem.new())
	var larva := Node2D.new()
	larva.add_to_group("larvae")
	add_child_autofree(larva)

	pickup._on_body_entered(larva)

	assert_false(pickup.is_queued_for_deletion())


func test_without_an_item_assigned_is_a_noop() -> void:
	var pickup := _make_pickup(null)
	var spider := _make_spider_with_status()

	pickup._on_body_entered(spider) # must not error

	assert_false(pickup.is_queued_for_deletion())
