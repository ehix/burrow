class_name Hitbox
extends Area2D
## A damage-dealing area. On overlap with a Hurtbox it applies `damage`.
## Used for contact damage; web shots deal damage through their own script but
## reuse the same Hurtbox target.

@export var damage: float = 10.0

signal hit(hurtbox: Hurtbox)


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if area is Hurtbox:
		area.receive_hit(damage, get_parent())
		hit.emit(area)
