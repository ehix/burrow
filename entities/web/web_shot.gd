class_name WebShot
extends Area2D
## A web-shot projectile. Travels along its launch direction and resolves by what
## it strikes: an enemy/player hurtbox takes light damage plus an entangling web
## effect (slow + knockback shove + brief stun + distress flash); a larva is
## web-killed into an inedible corpse; a placed web trap takes a destructive hit;
## a wall just stops it. Collision mask = world(1) | larva(8) | hurtbox(16) |
## trap(32) = 57. Walls/larvae/traps arrive via body_entered, hurtboxes via
## area_entered. The shot is not on any layer and never hits its own shooter.

const SpentScene := preload("res://entities/web/web_shot_spent.tscn")

@export var speed: float = 340.0
## Light HP damage on a hurtbox hit (a web entangles more than it wounds).
@export var damage: float = 8.0
@export var max_lifetime: float = 2.0
## Entangle: drop the victim's move speed to this fraction for slow_duration.
@export var slow_factor: float = 0.4
@export var slow_duration: float = 2.0
## The victim is shoved one tile along the shot's travel and stunned briefly.
@export var stun_duration: float = 0.25

var _velocity := Vector2.ZERO
var _source: Node = null
var _spent := false
var _life := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


## Called by WebEmitter right after spawn.
func launch(direction: Vector2, source: Node) -> void:
	var dir := direction.normalized()
	_velocity = dir * speed
	_source = source
	rotation = dir.angle()


func _physics_process(delta: float) -> void:
	global_position += _velocity * delta
	_life += delta
	if _life >= max_lifetime:
		_despawn()


func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	if body is WebTrap:
		(body as WebTrap).take_web_hit()
	elif body.is_in_group("larvae") and body.has_method("web_kill"):
		body.web_kill()
	# else: a wall — nothing to do but splat.
	_leave_splat()
	_despawn()


func _on_area_entered(area: Area2D) -> void:
	if _spent or not (area is Hurtbox):
		return
	if _is_source(area):
		return
	area.receive_hit(damage, _source)
	var entity := _entity_of(area)
	if entity != null and entity.has_method("apply_web_hit"):
		entity.apply_web_hit(_push_dir(), slow_factor, slow_duration, stun_duration)
	_despawn()


## The dominant cardinal the shot is travelling — the direction it shoves a hit.
func _push_dir() -> Vector2i:
	if absf(_velocity.x) >= absf(_velocity.y):
		return Vector2i(int(signf(_velocity.x)), 0)
	return Vector2i(0, int(signf(_velocity.y)))


func _entity_of(hurtbox: Area2D) -> Node:
	if hurtbox.owner != null:
		return hurtbox.owner
	return hurtbox.get_parent()


func _leave_splat() -> void:
	var holder := get_parent()
	if holder == null:
		return
	var splat := SpentScene.instantiate()
	holder.add_child(splat)
	splat.global_position = global_position
	splat.rotation = rotation


func _is_source(hurtbox: Area2D) -> bool:
	return hurtbox.owner == _source or hurtbox.get_parent() == _source


func _despawn() -> void:
	if _spent:
		return
	_spent = true
	queue_free()
