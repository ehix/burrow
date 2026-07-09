class_name Hurtbox
extends Area2D
## An entity's damageable area. Forwards hits to its HealthComponent.
## Web shots (and future contact hitboxes) look for a Hurtbox to damage.
##
## health_path is resolved in _ready() rather than exported as a direct
## HealthComponent reference: a hand-written NodePath value in a .tscn does
## not auto-resolve into a Node-typed @export (it silently stays null), which
## is exactly what left melee/web-shot damage a no-op on both spiders.
##
## Every existing attack (melee, web shot) resolves through receive_hit(), so
## it's also the single choke point for the Camouflage guardrail: an attack
## registering here breaks Camouflage on both the victim (this Hurtbox's
## owner) and the attacker (`source`), if either has it active.

@export var health_path: NodePath
var health: HealthComponent

signal took_hit(amount: float, source: Node)


func _ready() -> void:
	if health == null and not health_path.is_empty():
		health = get_node_or_null(health_path) as HealthComponent


func receive_hit(amount: float, source: Node = null) -> void:
	took_hit.emit(amount, source)
	CamouflageSkill.break_if_present(get_parent())
	CamouflageSkill.break_if_present(source)
	if health != null:
		health.take_damage(amount)
