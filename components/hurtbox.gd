class_name Hurtbox
extends Area2D
## An entity's damageable area. Forwards hits to its HealthComponent.
## Web shots (and future contact hitboxes) look for a Hurtbox to damage.
##
## health_path is resolved in _ready() rather than exported as a direct
## HealthComponent reference: a hand-written NodePath value in a .tscn does
## not auto-resolve into a Node-typed @export (it silently stays null), which
## is exactly what left melee/web-shot damage a no-op on both spiders.

@export var health_path: NodePath
var health: HealthComponent

signal took_hit(amount: float, source: Node)


func _ready() -> void:
	if health == null and not health_path.is_empty():
		health = get_node_or_null(health_path) as HealthComponent


func receive_hit(amount: float, source: Node = null) -> void:
	took_hit.emit(amount, source)
	if health != null:
		health.take_damage(amount)
