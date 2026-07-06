class_name TrapPlacer
extends Node
## Places web traps, capped at max_active simultaneous traps per owner.
## Freed traps (spent on consumption, or level teardown) are pruned lazily.

@export var trap_scene: PackedScene
@export var max_active: int = 3

var _active: Array[Node] = []


func can_place() -> bool:
	_prune()
	return trap_scene != null and _active.size() < max_active


func active_count() -> int:
	_prune()
	return _active.size()


## Place a trap at a world position, owned by `placer`. Returns the trap, or
## null if at the active cap / unconfigured.
func place(at_position: Vector2, placer: Node) -> Node:
	if not can_place():
		return null
	var trap := trap_scene.instantiate()
	_spawn_parent(placer).add_child(trap)
	trap.global_position = at_position
	if trap.has_method("setup"):
		trap.setup(placer)
	_active.append(trap)
	return trap


func _prune() -> void:
	_active = _active.filter(func(t: Node) -> bool: return is_instance_valid(t))


func _spawn_parent(placer: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return placer.get_tree().current_scene
