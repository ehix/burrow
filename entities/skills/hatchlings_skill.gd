class_name HatchlingsSkill
extends SkillComponent
## Wolf Spider (female): spawns `spawn_count` temporary hatchling scouts that
## hunt independently for `lifetime` seconds, then despawn. `hatchling_scene`
## is a small CharacterBody2D (own GridMover + a light Hitbox) — not yet
## authored as a `.tscn` (needs an editor pass for its collision/visual), but
## its script contract (`setup(owner, lifetime)`) is fixed here.

@export var hatchling_scene: PackedScene
@export var spawn_count: int = 3
@export var lifetime: float = 8.0
@export var spawn_radius: float = 24.0


func _on_activate(source: Node) -> void:
	if hatchling_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var holder := _spawn_parent(source)
	for i in spawn_count:
		var hatchling := hatchling_scene.instantiate()
		holder.add_child(hatchling)
		var offset := Vector2(spawn_radius, 0).rotated(TAU * float(i) / float(spawn_count))
		hatchling.global_position = origin.global_position + offset
		if hatchling.has_method("setup"):
			hatchling.setup(source, lifetime, offset)


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
