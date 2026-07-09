class_name FungusSenseItem
extends ConsumableItem
## Fungus (X Variant): temporarily triggers the Sense skill's x-ray reveal
## (see SenseSkill) without needing the skill's own cooldown/hunger cost —
## eating it is the trigger, at zero action cost.

@export var duration: float = 6.0


func _init() -> void:
	item_id = &"fungus_sense"


func apply(consumer: Node) -> void:
	var status := _status_of(consumer)
	if status != null:
		status.apply(&"sense", 1.0, duration)


func _status_of(entity: Node) -> StatusEffectComponent:
	for child in entity.get_children():
		if child is StatusEffectComponent:
			return child
	return null
