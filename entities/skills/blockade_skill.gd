class_name BlockadeSkill
extends SkillComponent
## Funnel/Weaver Spider (male): deploys a destructible rock/dirt barrier.
## Unlike WebTrap (never blocks movement, just slows), a blockade is a hard
## obstacle until destroyed. Placing one directly over a pit tile also patches
## it for ground traversal, via Level.patch_pit_at — the same mechanism the
## ceiling plane already bypasses structurally (see CeilingData).
## `blockade_scene` is a high-durability StaticBody2D — not yet authored,
## contract fixed here: its script must call `setup(hits_to_destroy)`.

@export var hits_to_destroy: int = 6
@export var blockade_scene: PackedScene


func _on_activate(source: Node) -> void:
	if blockade_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var blockade := blockade_scene.instantiate()
	_spawn_parent(source).add_child(blockade)
	blockade.global_position = origin.global_position
	if blockade.has_method("setup"):
		blockade.setup(hits_to_destroy)
	var level := source.get_tree().get_first_node_in_group("level") as Level
	if level != null:
		level.patch_pit_at(level.tile_of(origin.global_position))


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
