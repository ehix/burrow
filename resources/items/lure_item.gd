class_name LureItem
extends ConsumableItem
## Deployable, not consumed by a spider: emits a radial pulse that overrides
## nearby larvae's wander AI, drawing them toward its position for `duration`.
## `apply()` is a no-op here — a lure targets larvae directly, not whoever
## deployed it. `draw_larvae_within()` is the query a placed lure's own scene
## script would call each tick to find who it's currently pulling; steering
## those larvae toward the lure is left as an extension point since
## `Larva._wander_step()` has no pathfinding-toward-a-point seam yet.

@export var pulse_radius: float = 200.0
@export var duration: float = 60.0


func _init() -> void:
	item_id = &"lure"


func apply(_consumer: Node) -> void:
	pass


func draw_larvae_within(tree: SceneTree, origin: Vector2) -> Array:
	var drawn: Array = []
	for node in tree.get_nodes_in_group("larvae"):
		var larva := node as Node2D
		if larva != null and larva.global_position.distance_to(origin) <= pulse_radius:
			drawn.append(larva)
	return drawn
