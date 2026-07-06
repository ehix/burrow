class_name Hurtbox
extends Area2D
## An entity's damageable area. Forwards hits to its HealthComponent.
## Web shots (and future contact hitboxes) look for a Hurtbox to damage.

@export var health: HealthComponent

signal took_hit(amount: float, source: Node)


func receive_hit(amount: float, source: Node = null) -> void:
	took_hit.emit(amount, source)
	if health != null:
		health.take_damage(amount)
