class_name WebEmitter
extends Node
## Fires a web-shot projectile along a facing direction, on a cooldown.
## Shots are parented to the shooter's container (the Level's Entities node) so
## they keep flying independently of the shooter.

@export var web_shot_scene: PackedScene
@export var cooldown: float = 0.6
## How far ahead of the shooter the shot spawns (clears its own body).
@export var muzzle_offset: float = 18.0
## Hunger added to *every* spider per shot — the metabolic tax that keeps firing
## from being free (no hard ammo cap; hunger regulates spam).
@export var hunger_cost: float = 4.0

var _cooldown_left: float = 0.0


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)


func can_fire() -> bool:
	return _cooldown_left <= 0.0 and web_shot_scene != null


## Fire along `direction`. Returns the spawned shot, or null if on cooldown /
## unconfigured / no direction.
func fire(from_position: Vector2, direction: Vector2, source: Node) -> Node:
	var dir := direction.normalized()
	if not can_fire() or dir == Vector2.ZERO:
		return null
	_cooldown_left = cooldown
	var shot := web_shot_scene.instantiate()
	_spawn_parent(source).add_child(shot)
	shot.global_position = from_position + dir * muzzle_offset
	if shot.has_method("launch"):
		shot.launch(dir, source)
	HungerComponent.charge_all(source.get_tree(), hunger_cost)
	return shot


func _spawn_parent(source: Node) -> Node:
	var holder := get_parent()
	if holder != null and holder.get_parent() != null:
		return holder.get_parent()
	return source.get_tree().current_scene
