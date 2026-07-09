class_name StatusEffectComponent
extends Node
## Unified tick-based store for timed buffs/debuffs (Poison, Speed, Sense,
## Armor, ...) — guardrail: re-applying an id already active refreshes its
## duration/magnitude in place instead of stacking a second competing timer
## for the same slot. That collision is what "overlapping buff crashes" meant
## in practice: two independent timers fighting over one mutable field (e.g.
## GridMover.speed_scale) so whichever expires first silently undoes the
## other's effect early.

signal effect_applied(id: StringName, magnitude: float, duration: float)
signal effect_expired(id: StringName)

class ActiveEffect:
	var magnitude: float
	var time_left: float
	var on_tick: Callable
	var on_expire: Callable

var _effects: Dictionary = {}  # StringName -> ActiveEffect


func _process(delta: float) -> void:
	tick(delta)


## Advance every active effect by `delta`: run its on_tick (if any), then
## expire it once its time runs out. Exposed separately from _process so
## tests can drive it deterministically without physics frames.
func tick(delta: float) -> void:
	for id in _effects.keys().duplicate():
		var fx: ActiveEffect = _effects[id]
		if fx.on_tick.is_valid():
			fx.on_tick.call(delta, fx.magnitude)
		fx.time_left -= delta
		if fx.time_left <= 0.0:
			_expire(id)


## Apply or refresh a named effect. Re-applying the same id replaces its
## magnitude/duration (and callbacks, if given) rather than adding a second
## timer for it — the refresh-not-stack guardrail.
func apply(id: StringName, magnitude: float, duration: float,
		on_tick := Callable(), on_expire := Callable()) -> void:
	if _effects.has(id):
		var existing: ActiveEffect = _effects[id]
		existing.magnitude = magnitude
		existing.time_left = duration
		if on_tick.is_valid():
			existing.on_tick = on_tick
		if on_expire.is_valid():
			existing.on_expire = on_expire
		return
	var fx := ActiveEffect.new()
	fx.magnitude = magnitude
	fx.time_left = duration
	fx.on_tick = on_tick
	fx.on_expire = on_expire
	_effects[id] = fx
	effect_applied.emit(id, magnitude, duration)
	if get_parent() != null:
		EventBus.status_effect_applied.emit(get_parent(), id, magnitude, duration)


func has(id: StringName) -> bool:
	return _effects.has(id)


func magnitude(id: StringName) -> float:
	var fx: ActiveEffect = _effects.get(id)
	return fx.magnitude if fx != null else 0.0


func time_left(id: StringName) -> float:
	var fx: ActiveEffect = _effects.get(id)
	return fx.time_left if fx != null else 0.0


## Copy every effect active on this component onto `other`, preserving each
## one's remaining time and callbacks. Backs NetProjectileSkill's "inherits
## status effects" clause (e.g. a poisoned Net-Caster's net carries Poison
## onto whatever it immobilizes).
func copy_active_into(other: StatusEffectComponent) -> void:
	for id in _effects:
		var fx: ActiveEffect = _effects[id]
		other.apply(id, fx.magnitude, fx.time_left, fx.on_tick, fx.on_expire)


func _expire(id: StringName) -> void:
	var fx: ActiveEffect = _effects[id]
	_effects.erase(id)
	if fx.on_expire.is_valid():
		fx.on_expire.call()
	effect_expired.emit(id)
	if get_parent() != null:
		EventBus.status_effect_expired.emit(get_parent(), id)
