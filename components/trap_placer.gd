class_name TrapPlacer
extends Node
## Places web traps. There is no hard cap on simultaneous traps — the hunger
## cost of laying one is what regulates spam. Freed traps (spent on consumption,
## or level teardown) are still tracked and pruned lazily for active_count().

@export var trap_scene: PackedScene
## Hunger added to *every* spider per trap laid — the metabolic tax that keeps
## trap-laying from being free (hunger regulates spam, no hard cap on webs).
@export var hunger_cost: float = 6.0

var _active: Array[Node] = []


func can_place() -> bool:
	return trap_scene != null


func active_count() -> int:
	_prune()
	return _active.size()


## Place a trap at a world position, owned by `placer`, on `plane` (the plane
## `placer` occupied at the moment of placement — WebTrap uses this so a
## ceiling-laid web never catches a ground larva or entangles a ground
## spider). Returns the trap, or null if at the active cap / unconfigured.
func place(at_position: Vector2, placer: Node, plane: Level.Layer = Level.Layer.GROUND) -> Node:
	if not can_place():
		return null
	var trap := trap_scene.instantiate()
	_spawn_parent(placer).add_child(trap)
	trap.global_position = at_position
	if trap.has_method("setup"):
		trap.setup(placer, plane)
	_active.append(trap)
	HungerComponent.charge_all(placer.get_tree(), hunger_cost)
	return trap


func _prune() -> void:
	_active = _active.filter(func(t: Node) -> bool: return is_instance_valid(t))


func _spawn_parent(placer: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return placer.get_tree().current_scene
