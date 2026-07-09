class_name FungusPoisonItem
extends ConsumableItem
## Grants the consumer venomous attacks for `buff_duration`: every standard
## attack they land (melee, web projectile, web trap residue) also inflicts a
## Poison DoT on the victim. The consumer's own StatusEffectComponent just
## holds the "venomous" tag + its magnitude; each attack call site is
## expected to call the static `apply_venom_on_hit()` after resolving its
## normal damage — not yet wired into Player._melee / WebEmitter / WebTrap in
## this pass.

@export var venom_damage_per_tick: float = 2.0
@export var venom_duration: float = 3.0
@export var buff_duration: float = 20.0


func _init() -> void:
	item_id = &"fungus_poison"


func apply(consumer: Node) -> void:
	var status := _status_of(consumer)
	if status != null:
		status.apply(&"venomous", venom_damage_per_tick, buff_duration)


## Call from an attack's hit-resolution (after normal damage) with the
## attacker and the landed victim. No-op if the attacker isn't venomous.
static func apply_venom_on_hit(attacker: Node, victim: Node) -> void:
	var attacker_status := _status_of(attacker)
	if attacker_status == null or not attacker_status.has(&"venomous"):
		return
	var victim_status := _status_of(victim)
	var victim_health := _health_of(victim)
	if victim_status == null or victim_health == null:
		return
	var dot := attacker_status.magnitude(&"venomous")
	victim_status.apply(&"poison", dot, 3.0,
		func(delta: float, magnitude: float) -> void: victim_health.take_damage(magnitude * delta))


static func _status_of(entity: Node) -> StatusEffectComponent:
	for child in entity.get_children():
		if child is StatusEffectComponent:
			return child
	return null


static func _health_of(entity: Node) -> HealthComponent:
	for child in entity.get_children():
		if child is HealthComponent:
			return child
	return null
