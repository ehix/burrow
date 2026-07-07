class_name HungerComponent
extends Node
## Hunger that rises over time and, once maxed, drains a sibling
## HealthComponent (starvation). Eating a larva calls satiate().
##
## Growth/drain live in tick(delta) rather than _process so tests can advance
## time deterministically. Self-contained: emits local signals; the owner
## relays overflow to EventBus.excess_consumed.

signal hunger_changed(value: float, max_value: float)
signal became_starving
signal overflowed(amount: float)  ## a meal pushed hunger past full

@export var max_hunger: float = 100.0
## Hunger gained per second.
@export var hunger_rate: float = 4.0
## HP lost per second while hunger is maxed.
@export var starvation_damage_rate: float = 6.0
## Sibling HealthComponent to drain when starving. Auto-found among siblings if
## left empty.
@export var health_path: NodePath

var current_hunger: float = 0.0
var health: HealthComponent

var _was_starving := false


func _ready() -> void:
	if health == null:
		if not health_path.is_empty():
			health = get_node_or_null(health_path) as HealthComponent
		else:
			health = _find_sibling_health()
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	tick(delta)


## Advance hunger by `delta` seconds and apply starvation damage if maxed.
func tick(delta: float) -> void:
	if current_hunger < max_hunger:
		current_hunger = minf(max_hunger, current_hunger + hunger_rate * delta)
		hunger_changed.emit(current_hunger, max_hunger)
	if is_starving():
		if not _was_starving:
			_was_starving = true
			became_starving.emit()
		if health != null:
			health.take_damage(starvation_damage_rate * delta)
	else:
		_was_starving = false


## Eat: reduce hunger by `amount`. Returns the overflow (how far the meal
## pushed past full, >= 0), and emits overflowed() when that is positive.
func satiate(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var overflow := maxf(0.0, amount - current_hunger)
	current_hunger = maxf(0.0, current_hunger - amount)
	hunger_changed.emit(current_hunger, max_hunger)
	if overflow > 0.0:
		overflowed.emit(overflow)
	return overflow


## Raise hunger by `amount` (clamped to max). Used by the metabolic cost of
## firing webs and laying traps — actions make every spider hungrier.
func add(amount: float) -> void:
	if amount <= 0.0:
		return
	current_hunger = minf(max_hunger, current_hunger + amount)
	hunger_changed.emit(current_hunger, max_hunger)


## Charge every spider in the scene `amount` hunger. The metabolic tax on a web
## action applies to all spiders, so spamming shots/traps is self-limiting.
static func charge_all(tree: SceneTree, amount: float) -> void:
	if tree == null or amount <= 0.0:
		return
	for spider in tree.get_nodes_in_group("spiders"):
		for child in spider.get_children():
			if child is HungerComponent:
				(child as HungerComponent).add(amount)


func is_starving() -> bool:
	return current_hunger >= max_hunger


func fraction() -> float:
	return current_hunger / max_hunger if max_hunger > 0.0 else 0.0


func _find_sibling_health() -> HealthComponent:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is HealthComponent:
			return child
	return null
