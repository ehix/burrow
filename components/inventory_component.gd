class_name InventoryComponent
extends Node
## Single-slot item carry for a spider (item/inventory rework). Player holds
## a picked-up item until use() is called on button-press; auto_use makes
## Enemy consume/deploy the instant it picks something up, reproducing the
## old walk-over-instant-consume behavior through this same component
## rather than a second code path.

const LurePulseScene := preload("res://entities/items/lure_pulse.tscn")

## Enemy sets this true (it has no button-press input to hook a "use"
## decision into); Player leaves it false. Side effect, accepted as intended:
## an auto_use holder that picks up a Lure deploys it at its own position,
## pulling larvae toward itself rather than the player — not an oversight.
@export var auto_use: bool = false

var held_item: ConsumableItem = null

## Emitted with the newly-held item, or null when the slot empties (used,
## deployed, or restored empty on a fresh descent).
signal item_held_changed(item: ConsumableItem)


## Fills the slot with `item` if empty. Returns false (no-op — the item
## stays wherever it was) if already holding something. `consumer` is only
## used if auto_use immediately triggers use().
func try_pickup(item: ConsumableItem, consumer: Node) -> bool:
	if held_item != null:
		return false
	held_item = item
	item_held_changed.emit(held_item)
	if auto_use:
		use(consumer)
	return true


## Consumes or deploys the held item. No-op if the slot is empty.
func use(consumer: Node) -> void:
	if held_item == null:
		return
	if held_item is LureItem:
		var lure := LurePulseScene.instantiate()
		lure.item = held_item as LureItem
		_spawn_parent().add_child(lure)
		if consumer is Node2D:
			lure.global_position = (consumer as Node2D).global_position
	else:
		held_item.apply(consumer)
	held_item = null
	item_held_changed.emit(null)


## A deployed Lure should live alongside the spider in the level's entity
## tree, not as this component's own child (which would free it the instant
## the spider dies/the level tears down its children individually) — mirrors
## TrapPlacer._spawn_parent()'s grandparent-walk.
func _spawn_parent() -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return get_tree().current_scene
