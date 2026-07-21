class_name CentipedeSegment
extends StaticBody2D
## One tile-sized block of a Centipede's body (Centipede entity, sub-project
## H): purely physical/visual, holds no state of its own beyond its current
## radius/tint. `take_hit()` forwards straight to the parent Centipede so
## every segment contributes to the same shared hit counter -- hitting any
## part of the body counts.
##
## Visual: a shaded sphere (three layered draw_circle() calls: shadow-
## offset base, main fill, highlight), no sprite art -- pure geometry was a
## deliberate final choice after 3 rounds of AI-generated sprite art didn't
## converge (see docs/superpowers/specs/2026-07-21-centipede-procedural-
## geometry-design.md). radius_for_index() picks HEAD/BODY/TAIL_RADIUS
## purely from a segment's position in Centipede._tiles -- no per-role
## rotation or shape is needed, since a sphere looks identical from every
## angle, unlike the sprite-based design this replaced.

const HEAD_RADIUS := 24.0
const BODY_RADIUS := 22.0
const TAIL_RADIUS := 17.0

## Wide earthy hue range (brown/umber through olive-green), muted
## saturation/value -- see design doc §4 for the full reasoning. First-pass
## numbers, easy to retune during playtest.
const HUE_MIN := 0.05
const HUE_MAX := 0.40
const SATURATION_MIN := 0.35
const SATURATION_MAX := 0.6
const VALUE_MIN := 0.35
const VALUE_MAX := 0.55

var _radius: float = BODY_RADIUS
var _tint: Color = Color(0.3, 0.45, 0.2)


func _ready() -> void:
	add_to_group("centipede_segments")
	# Always renders at its own literal authored color, never relit by the
	# player's VisionLight (playtest finding, same root cause and fix as
	# Blockade.gd's own).
	material = CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED


## Assigns this segment's size/color and requests a redraw.
func set_visual(radius: float, tint: Color) -> void:
	_radius = radius
	_tint = tint
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(2, 3), _radius, _tint.darkened(0.4))
	draw_circle(Vector2.ZERO, _radius - 2.0, _tint)
	draw_circle(Vector2(-_radius * 0.22, -_radius * 0.25), _radius * 0.45, _tint.lightened(0.18))


## Which radius a segment at `index` within a body of `count` segments
## needs, purely from its position -- pure function so it's directly
## unit-testable without a scene tree, matching this codebase's established
## pattern for this kind of logic (e.g. MazeRenderer.wall_occludes_extent()).
static func radius_for_index(index: int, count: int) -> float:
	if count <= 1 or index == 0:
		return HEAD_RADIUS
	if index == count - 1:
		return TAIL_RADIUS
	return BODY_RADIUS


static func random_body_color() -> Color:
	return Color.from_hsv(
		randf_range(HUE_MIN, HUE_MAX),
		randf_range(SATURATION_MIN, SATURATION_MAX),
		randf_range(VALUE_MIN, VALUE_MAX)
	)


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
