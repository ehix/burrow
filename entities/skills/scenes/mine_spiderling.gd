class_name MineSpiderling
extends Node2D
## Egg Mine's cosmetic burst flourish (skill fixes bundle) — appears at a
## radial offset when a mine detonates, waits `explode_after`, deals one
## tiny damage tick to whatever's still nearby, then frees. Not an attacker:
## no movement, no chase, no persistent AI — CocoonMine's real damage
## already landed via its own direct burst_damage on the trigger.
## Placeholder visual: a small drawn dot, no art asset yet.

@export var damage: float = 1.0
@export var damage_radius: float = 24.0
@export var explode_after: float = 0.3

var _time_left: float = 0.0
var _started: bool = false


func _ready() -> void:
	add_to_group("mine_spiderlings")


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color(0.85, 0.3, 0.3, 0.9))


func _physics_process(delta: float) -> void:
	if not _started:
		_time_left = explode_after
		_started = true
	_time_left -= delta
	if _time_left <= 0.0:
		_explode()


func _explode() -> void:
	for group in ["spiders", "larvae"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body == null or body.global_position.distance_to(global_position) > damage_radius:
				continue
			var hurtbox := body.get_node_or_null("Hurtbox") as Hurtbox
			if hurtbox != null:
				hurtbox.receive_hit(damage, self)
	queue_free()
