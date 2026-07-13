class_name CentipedeSegment
extends StaticBody2D
## One tile-sized block of a Centipede's body (Centipede entity, sub-project
## H): purely physical/visual, holds no state of its own. `take_hit()`
## forwards straight to the parent Centipede so every segment contributes to
## the same shared hit counter -- hitting any part of the body counts.
## Placeholder visual: a drawn segment shape, no art asset yet (mirrors
## Earthworm/Blockade's own "no art asset yet" precedent).

func _ready() -> void:
	add_to_group("centipede_segments")


func _draw() -> void:
	var half := Vector2(20.0, 20.0)
	draw_rect(Rect2(-half, half * 2.0), Color(0.3, 0.45, 0.2, 0.9))


## Forwards to the owning Centipede's shared counter -- called by WebShot
## (physics overlap) and by Player/Enemy's melee (exact-tile lookup via
## Centipede.segment_at_tile()) identically; the segment itself never tracks
## a hit count.
func take_hit() -> void:
	var parent := get_parent()
	if parent != null and parent.has_method("take_hit"):
		parent.take_hit()
