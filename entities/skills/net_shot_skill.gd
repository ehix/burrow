class_name NetShotSkill
extends SkillComponent
## Net-Casting Spider: fires the currently-held trap as a fast capture shot
## (Net-caster rework). Only activates while `net_hold.is_holding()` is true
## — firing empty-handed is a no-op, no cooldown/hunger spent. On a landed
## hit it dispatches by victim type: a spider gets the unchanged pre-rework
## hard immobilize (2.5s hard stun, no slow) plus a copy of the shooter's own
## active status effects (e.g. Poison picked up from Fungal Larva); a larva
## is captured alive — see resolve_larva_hit().
##
## `net_shot_scene` is the fast projectile scene (entities/skills/scenes/
## net_shot.gd/.tscn) whose own script calls back into resolve_hit()/
## resolve_larva_hit() below on landing.

@export var net_shot_scene: PackedScene
@export var muzzle_offset: float = 18.0
@export var immobilize_duration: float = 2.5

## Set externally by whichever caller wires this skill's sibling NetHoldSkill
## — Player._ready() for the player, Enemy._make_skills() for the enemy. Not
## an @export/NodePath since Enemy constructs skills dynamically via .new().
var net_hold: NetHoldSkill = null

const WebTrapScene := preload("res://entities/web/web_trap.tscn")


func activate(source: Node) -> bool:
	if net_hold == null or not net_hold.is_holding():
		return false
	return super.activate(source)


func _on_activate(source: Node) -> void:
	net_hold.spend()
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


## Called by the net shot's own script when it lands a hit on a spider.
## Unchanged from the pre-rework NetProjectileSkill: a hard, full stun with
## no slow, plus a copy of the shooter's active status effects.
func resolve_hit(shooter: Node, victim: Node) -> void:
	if victim.has_method("apply_web_hit"):
		victim.apply_web_hit(Vector2i.ZERO, 1.0, 0.0, immobilize_duration)
	_copy_status_effects(shooter, victim)


## Called by the net shot's own script when it lands on a larva: captures it
## alive at the impact point using the same WebTrap machinery a normally
## -placed trap uses (including its own auto-consume-if-a-spider-is-standing
## -there path), instead of killing it outright. Setup with the shooter's own
## plane (mirrors TrapPlacer.place()) so WebTrap's plane gate still applies —
## a ceiling-fired shot can't capture a ground larva just because the
## projectile itself doesn't distinguish planes physically.
func resolve_larva_hit(shooter: Node, larva: Node, at_position: Vector2) -> void:
	var trap: WebTrap = WebTrapScene.instantiate()
	_spawn_parent(shooter).add_child(trap)
	trap.global_position = at_position
	trap.setup(shooter, _plane_of(shooter))
	trap.catch_larva(larva)


## Mirrors BlockadeSkill._plane_of()/CocoonMine._plane_of(): PlaneComponent-
## tracked plane, or GROUND for anything without one.
func _plane_of(source: Node) -> Level.Layer:
	var plane_component: PlaneComponent = source.get("_plane") if "_plane" in source else null
	if plane_component != null:
		return plane_component.current_plane
	return Level.Layer.GROUND


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
