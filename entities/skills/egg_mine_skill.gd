class_name EggMineSkill
extends SkillComponent
## Wolf Spider (female): places a hidden cocoon mine that detonates when a
## player/enemy steps within its trigger radius, releasing `burst_count` tiny
## damaging spiderlings (the aggressive counterpart to Hatchlings' scouting
## mode). `mine_scene` is a static Area2D — not yet authored, contract fixed
## here: its script must call `arm(owner, burst_count)` and handle its own
## proximity detonation.

@export var mine_scene: PackedScene
@export var burst_count: int = 4


func _on_activate(source: Node) -> void:
	if mine_scene == null:
		return
	var origin := source as Node2D
	if origin == null:
		return
	var mine := mine_scene.instantiate()
	_spawn_parent(source).add_child(mine)
	mine.global_position = origin.global_position
	if mine.has_method("arm"):
		mine.arm(source, burst_count, _plane_of(source))


## Mirrors BlockadeSkill._plane_of(): the plane `source` currently occupies.
func _plane_of(source: Node) -> Level.Layer:
	var plane_component: PlaneComponent = source.get("_plane") if "_plane" in source else null
	if plane_component != null:
		return plane_component.current_plane
	return Level.Layer.GROUND


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
