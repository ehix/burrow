class_name LurePulse
extends Node2D
## Lure (design §5): a placed item that emits a radial pulse pulling nearby
## larvae toward it, every PULSE_INTERVAL seconds for `item.duration`, then
## disappears. Unlike the other consumables (WorldItemPickup), a Lure is
## never picked up by a spider — it's active the moment it's placed.
## Placeholder visual: a pulsing ring, no art asset yet.

const PULSE_INTERVAL := 0.5

@export var item: LureItem

var _time_left: float = 0.0
var _pulse_accum: float = 0.0


func _ready() -> void:
	add_to_group("world_items")
	if item != null:
		_time_left = item.duration


func _draw() -> void:
	if item == null:
		return
	draw_arc(Vector2.ZERO, item.pulse_radius, 0.0, TAU, 24, Color(0.6, 0.85, 1.0, 0.25), 2.0)
	draw_circle(Vector2.ZERO, 6.0, Color(0.6, 0.85, 1.0, 0.9))


func _physics_process(delta: float) -> void:
	if item == null:
		queue_free()
		return
	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()
		return
	_pulse_accum += delta
	if _pulse_accum >= PULSE_INTERVAL:
		_pulse_accum = 0.0
		_pulse()


func _pulse() -> void:
	for larva in item.draw_larvae_within(get_tree(), global_position):
		if larva.has_method("nudge_toward"):
			larva.nudge_toward(global_position)
