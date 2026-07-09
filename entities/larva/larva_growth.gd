class_name LarvaGrowth
extends Node
## Scales a larva's visual size and heal-on-consume value with how long it has
## survived (design §2: Larvae Mechanics). Ticks independently of the eating
## path — a larva keeps aging while wandering, and while caught in a web too,
## so `tick()` has no early-out for `caught`. Not yet attached to
## `larva.tscn`/wired into Enemy/Player's eat calls in this pass: those
## currently spend a flat `eat_satiation`; hook `heal_value()` in as its
## replacement.

const GROWTH_RATE: float = 0.02      # size_scale gained per second alive
const MAX_SIZE_SCALE: float = 2.5
const BASE_HEAL_VALUE: float = 40.0  # mirrors Enemy.eat_satiation's slice-1 default
const HEAL_PER_SIZE: float = 20.0    # extra heal per +1.0 size_scale over 1.0

var age: float = 0.0
var size_scale: float = 1.0


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	age += delta
	size_scale = minf(MAX_SIZE_SCALE, 1.0 + GROWTH_RATE * age)


## Hunger satiated / health restored when this larva is eaten right now.
func heal_value() -> float:
	return BASE_HEAL_VALUE + HEAL_PER_SIZE * (size_scale - 1.0)
