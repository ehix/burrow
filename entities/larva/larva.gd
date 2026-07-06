class_name Larva
extends CharacterBody2D
## A wandering creature. Drifts along its facing, reverses when it hits a wall,
## and freezes when a trap catches it. Body collides with walls only (mask =
## world) so it passes through traps and spiders until a trap's area catches it.

@export var speed: float = 42.0

var direction := Vector2.RIGHT
var caught := false


func _ready() -> void:
	add_to_group("larvae")
	_apply_rotation()


## Set initial facing (Level derives this from the spawn tile's type).
func set_facing(dir: Vector2i) -> void:
	if dir != Vector2i.ZERO:
		direction = Vector2(dir).normalized()
		_apply_rotation()


## Called by a trap: stop and snap to the trap centre.
func set_caught(at_position: Vector2) -> void:
	caught = true
	global_position = at_position
	velocity = Vector2.ZERO


func _physics_process(_delta: float) -> void:
	if caught:
		return
	velocity = direction * speed
	if move_and_slide():
		reverse()


func reverse() -> void:
	direction = -direction
	_apply_rotation()


func _apply_rotation() -> void:
	if direction != Vector2.ZERO:
		rotation = direction.angle()
