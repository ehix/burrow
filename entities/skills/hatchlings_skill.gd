class_name HatchlingsSkill
extends SkillComponent
## Wolf Spider (female): spawns `spawn_count` temporary hatchling scouts that
## hunt independently until killed — no fixed lifetime, they persist until
## a hit lands. `hatchling_scene`'s script contract is `setup(owner,
## escort_offset)`. The skill's own cooldown doesn't start counting down
## until every spawned hatchling has died — see
## SkillComponent._defer_cooldown()/_start_deferred_cooldown().

@export var hatchling_scene: PackedScene
@export var spawn_count: int = 3
@export var spawn_radius: float = 24.0

## The current batch's still-alive hatchlings — emptied as each one leaves
## the tree (dies), at which point the deferred cooldown finally starts.
var _alive: Array[Node] = []


func _defer_cooldown() -> bool:
	return true


func _on_activate(source: Node) -> void:
	_alive.clear()
	var origin := source as Node2D
	if hatchling_scene != null and origin != null:
		var holder := _spawn_parent(source)
		for i in spawn_count:
			var hatchling := hatchling_scene.instantiate()
			holder.add_child(hatchling)
			var offset := Vector2(spawn_radius, 0).rotated(TAU * float(i) / float(spawn_count))
			hatchling.global_position = origin.global_position + offset
			if hatchling.has_method("setup"):
				hatchling.setup(source, offset)
			_alive.append(hatchling)
			hatchling.tree_exited.connect(_on_hatchling_died.bind(hatchling))
	# Nothing actually spawned (bad config, or spawn_count <= 0) — don't get
	# stuck busy forever waiting for a death that will never come.
	if _alive.is_empty():
		_start_deferred_cooldown()


func _on_hatchling_died(hatchling: Node) -> void:
	_alive.erase(hatchling)
	if _alive.is_empty():
		_start_deferred_cooldown()


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
