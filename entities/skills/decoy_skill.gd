class_name DecoySkill
extends SkillComponent
## Decoy Spider (female): drops a static effigy on the map grid. `decoy_scene`'s
## script should add_to_group("spiders") — so Enemy's existing
## `_nearest_in_group`/perception keeps finding a valid target — AND a
## distinct "decoys" group, so a real spider's own combat/targeting logic can
## tell it apart from an actual threat. Not yet authored as a `.tscn`.

@export var decoy_scene: PackedScene
@export var lifetime: float = 10.0


func _on_activate(source: Node) -> void:
	if decoy_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var decoy := decoy_scene.instantiate()
	_spawn_parent(source).add_child(decoy)
	decoy.global_position = origin.global_position
	if decoy.has_method("setup"):
		decoy.setup(lifetime)


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
