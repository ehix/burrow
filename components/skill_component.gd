class_name SkillComponent
extends Node
## Base for an activatable spider skill: cooldown + hunger cost, mirroring the
## WebEmitter/TrapPlacer pattern so every skill — class specialisations
## (NetHold, Hatchlings, Blockade, Camouflage, ...) and general utilities
## (Sense, Remove Walls) alike — plugs into the same metabolic-cost economy
## (HungerComponent.charge_all) as every other action a spider takes.
## Subclasses implement `_on_activate()`.

@export var cooldown: float = 8.0
@export var hunger_cost: float = 10.0

var _cooldown_left: float = 0.0


func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


func can_activate() -> bool:
	return _cooldown_left <= 0.0


## Attempt to activate. Returns false on cooldown (no cost charged); starts
## the cooldown, charges hunger, and calls `_on_activate()` otherwise.
func activate(source: Node) -> bool:
	if not can_activate():
		return false
	_cooldown_left = cooldown
	HungerComponent.charge_all(source.get_tree(), hunger_cost)
	_on_activate(source)
	return true


## Override in subclasses.
func _on_activate(_source: Node) -> void:
	pass
