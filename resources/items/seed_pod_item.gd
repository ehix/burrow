class_name SeedPodItem
extends ConsumableItem
## Temporary percentage-based movement speed multiplier.

@export var speed_bonus: float = 0.4
@export var duration: float = 8.0


func _init() -> void:
	item_id = &"seed_pod"


func apply(consumer: Node) -> void:
	var status := _status_of(consumer)
	var mover := _mover_of(consumer)
	if status == null or mover == null:
		return
	status.apply(&"seed_haste", speed_bonus, duration,
		func(_delta: float, magnitude: float) -> void: mover.speed_scale = 1.0 + magnitude,
		func() -> void: mover.speed_scale = 1.0)


func _status_of(entity: Node) -> StatusEffectComponent:
	for child in entity.get_children():
		if child is StatusEffectComponent:
			return child
	return null


func _mover_of(entity: Node) -> GridMover:
	for child in entity.get_children():
		if child is GridMover:
			return child
	return null
