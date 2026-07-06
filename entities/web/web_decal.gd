class_name WebDecal
extends Sprite2D
## A short-lived cosmetic mark left behind by webs — a splat where a shot hit a
## wall, or a torn web where a trap was consumed. Holds, then fades out and
## frees itself. Purely visual: no collision, no gameplay effect.

@export var lifetime := 2.5
@export var fade_time := 1.0


func _ready() -> void:
	var hold := maxf(0.0, lifetime - fade_time)
	var tween := create_tween()
	tween.tween_interval(hold)
	tween.tween_property(self, "modulate:a", 0.0, fade_time)
	tween.tween_callback(queue_free)
