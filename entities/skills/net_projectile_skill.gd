class_name NetProjectileSkill
extends SkillComponent
## Net-Casting Spider (male): fires a forward, non-damaging net. On a landed
## hit it fully immobilizes the target for `immobilize_duration` (a hard stun,
## via GridMover.stun through apply_web_hit — no slow, no damage) and copies
## any of the shooter's own active status effects onto the victim (e.g.
## Poison picked up from Fungal Larva) — the "inherits status effects" clause.
##
## `net_shot_scene` is a PackedScene analogous to WebEmitter's web_shot_scene:
## an Area2D projectile whose own script calls back into `resolve_hit()`
## below on landing. Not yet authored (needs an editor pass for its
## collision/visual) — this script is the contract that scene's script calls
## into.

@export var net_shot_scene: PackedScene
@export var muzzle_offset: float = 18.0
@export var immobilize_duration: float = 2.5


func _on_activate(source: Node) -> void:
	if net_shot_scene == null:
		return
	var mover := source as Node2D
	if mover == null:
		return
	var facing: Vector2 = source.get("facing") if "facing" in source else Vector2.RIGHT
	var shot := net_shot_scene.instantiate()
	_spawn_parent(source).add_child(shot)
	shot.global_position = mover.global_position + facing * muzzle_offset
	if shot.has_method("launch"):
		shot.launch(facing, source, self)


## Called by the net projectile's own script when it lands a hit on `victim`.
func resolve_hit(shooter: Node, victim: Node) -> void:
	if victim.has_method("apply_web_hit"):
		victim.apply_web_hit(Vector2i.ZERO, 1.0, 0.0, immobilize_duration)
	_copy_status_effects(shooter, victim)


func _copy_status_effects(shooter: Node, victim: Node) -> void:
	var from := _status_of(shooter)
	var to := _status_of(victim)
	if from != null and to != null:
		from.copy_active_into(to)


func _status_of(entity: Node) -> StatusEffectComponent:
	for child in entity.get_children():
		if child is StatusEffectComponent:
			return child
	return null


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
