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
## Read-only HUD metadata (UI/HUD overhaul) — authored per skill instance in
## each class's .tscn, same pattern cooldown/hunger_cost already use.
@export var display_name: String = ""
@export var description: String = ""

var _cooldown_left: float = 0.0
## True while a subclass has deferred its real cooldown past activation (see
## _defer_cooldown()) — e.g. Hatchlings, whose cooldown shouldn't start
## counting down until every spawned minion has died. Gates can_activate()
## independently of _cooldown_left, which stays at 0 the whole time it's busy.
var _busy: bool = false


func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


func can_activate() -> bool:
	return not _busy and _cooldown_left <= 0.0


## How many seconds remain before can_activate() returns true again — the
## seam a HUD polls instead of reaching into the private _cooldown_left.
## While busy (see _defer_cooldown()), shows the frozen full `cooldown`
## value rather than a ticking-down one, since the real countdown hasn't
## started yet.
func remaining_cooldown() -> float:
	return cooldown if _busy else _cooldown_left


## Attempt to activate. Returns false on cooldown (no cost charged);
## otherwise starts the cooldown (or, for a skill that deferred it, marks it
## busy instead — see _defer_cooldown()), charges hunger, and calls
## `_on_activate()`.
func activate(source: Node) -> bool:
	if not can_activate():
		return false
	if _defer_cooldown():
		_busy = true
	else:
		_cooldown_left = cooldown
	HungerComponent.charge_all(source.get_tree(), hunger_cost)
	_on_activate(source)
	return true


## Override in a subclass that needs to start its real cooldown later than
## activation (e.g. once every spawned minion has died) instead of
## immediately. While deferred, the skill stays non-reactivatable
## (can_activate() stays false via the `_busy` gate above) until the
## subclass calls _start_deferred_cooldown().
func _defer_cooldown() -> bool:
	return false


## Called by a subclass that returned true from _defer_cooldown(), once
## ready to start the real cooldown countdown.
func _start_deferred_cooldown() -> void:
	_busy = false
	_cooldown_left = cooldown


## Override in subclasses.
func _on_activate(_source: Node) -> void:
	pass
