class_name WorldItemPickup
extends Area2D
## A world-placed pickup wrapping any ConsumableItem resource (design §5:
## Fungus Poison, Fungus Sense, Seed Pod). On a spider entering, routes
## through InventoryComponent.try_pickup() and frees itself only if the pickup
## succeeds (inventory had space). Placeholder visual: a coloured dot keyed
## by item_id, no art asset yet.
##
## Lure does NOT go through this path — see LurePulse. A Lure is active the
## moment it's placed, not picked up and consumed, so it isn't a
## WorldItemPickup at all.
##
## collision_mask = player(2) | enemy(4) = 6 — only spiders trigger it,
## larvae pass through untouched.

@export var item: ConsumableItem

var _spent := false


func _ready() -> void:
	add_to_group("world_items")
	body_entered.connect(_on_body_entered)


func _draw() -> void:
	var id: StringName = item.item_id if item != null else &""
	draw_circle(Vector2.ZERO, 7.0, ConsumableItem.ITEM_COLORS.get(id, Color.WHITE))


func _on_body_entered(body: Node2D) -> void:
	if _spent or item == null or not body.is_in_group("spiders"):
		return
	var inventory := _inventory_of(body)
	if inventory == null or not inventory.try_pickup(item, body):
		return
	_spent = true
	queue_free()


func _inventory_of(entity: Node) -> InventoryComponent:
	for child in entity.get_children():
		if child is InventoryComponent:
			return child
	return null
