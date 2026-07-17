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
	# Always renders at its own literal authored color, never relit by the
	# player's VisionLight (playtest finding, same root cause and fix as
	# Blockade.gd's own -- see its doc comment: a flat placeholder rect this
	# small reads with a visibly darker "outline" toward its own edges under
	# the light's real radial falloff, worst at exactly the close range a
	# segment usually gets seen at, since there's no real surface geometry
	# for that gradient to make sense across).
	material = CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


func _draw() -> void:
	var half := Vector2(20.0, 20.0)
	draw_rect(Rect2(-half, half * 2.0), Color(0.3, 0.45, 0.2, 0.9))


## Forwards to the owning Centipede's shared counter -- called by WebShot
## (physics overlap) and, via Centipede.hit_segment_at(), by Player/Enemy's
## melee too; the segment itself never tracks a hit count. `hit_direction`
## gives this segment the same nudge-and-slide-back bump Blockade.take_hit()
## uses (CombatFx.shunt) -- a hit visibly registers on the exact segment
## struck even though intact segments don't otherwise react.
func take_hit(hit_direction: Vector2 = Vector2.ZERO) -> void:
	CombatFx.shunt(self, hit_direction * 5.0)
	var parent := get_parent()
	if parent != null and parent.has_method("take_hit"):
		parent.take_hit()
