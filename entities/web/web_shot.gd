extends Area2D
## A web-shot projectile. Travels along its launch direction, damages the first
## hurtbox it hits (except the shooter's), and despawns on a wall or after its
## lifetime. Collision: mask = world(1) | hurtbox(16); it is not itself on any
## layer. Walls arrive via body_entered, hurtboxes via area_entered.

const SpentScene := preload("res://entities/web/web_shot_spent.tscn")

@export var speed: float = 340.0
@export var damage: float = 20.0
@export var max_lifetime: float = 2.0

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


func _on_body_entered(_body: Node2D) -> void:
	# Only world/wall bodies are in our mask — hitting one ends the shot.
	if _spent:
		return
	_leave_splat()
	_despawn()


func _leave_splat() -> void:
	var holder := get_parent()
	if holder == null:
		return
	var splat := SpentScene.instantiate()
	holder.add_child(splat)
	splat.global_position = global_position
	splat.rotation = rotation


func _on_area_entered(area: Area2D) -> void:
	if _spent or not (area is Hurtbox):
		return
	if _is_source(area):
		return
	area.receive_hit(damage, _source)
	_despawn()


func _is_source(hurtbox: Area2D) -> bool:
	return hurtbox.owner == _source or hurtbox.get_parent() == _source


func _despawn() -> void:
	if _spent:
		return
	_spent = true
	queue_free()
