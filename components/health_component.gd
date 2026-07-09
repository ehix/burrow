class_name HealthComponent
extends Node
## Reusable HP for any entity. Self-contained: emits local signals only, so it
## is trivially unit-testable. The owning entity relays to the EventBus/HUD.

signal health_changed(value: float, max_value: float)
signal damaged(amount: float)
signal died

@export var max_health: float = 100.0

var current_health: float


func _ready() -> void:
	if current_health <= 0.0:
		current_health = max_health


## Apply damage. Clamps at zero and emits `died` exactly once at the boundary.
func take_damage(amount: float) -> void:
	if amount <= 0.0 or is_dead():
		return
	if GameState.god_mode and _is_player_owned():
		return
	var previous := current_health
	current_health = maxf(0.0, current_health - amount)
	damaged.emit(amount)
	health_changed.emit(current_health, max_health)
	if current_health == 0.0 and previous > 0.0:
		died.emit()


## Restore HP, clamped at max_health.
func heal(amount: float) -> void:
	if amount <= 0.0 or is_dead():
		return
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)


func set_max_health(value: float, refill: bool = false) -> void:
	max_health = maxf(1.0, value)
	if refill:
		current_health = max_health
	else:
		current_health = minf(current_health, max_health)
	health_changed.emit(current_health, max_health)


func is_dead() -> bool:
	return current_health <= 0.0


func fraction() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0


## Dev god-mode (G) is scoped to the player: check the owner's group rather
## than a broad flag, so the enemy stays fully mortal while it's on.
func _is_player_owned() -> bool:
	var parent := get_parent()
	return parent != null and parent.is_in_group("player")
