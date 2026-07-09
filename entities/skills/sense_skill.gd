class_name SenseSkill
extends SkillComponent
## General utility (design §4): grants temporary x-ray vision through walls
## (structural layout, critters, hostile entities) for `duration`. Rendering
## (a full-map reveal pass over Renderer/Occluder visibility) isn't
## implemented here — this just owns the timed "sense" status tag; the
## fog/occluder layer would read `status.has(&"sense")` to decide whether to
## ignore LightOccluder2D this frame (extension point on MazeRenderer /
## Level.apply_darkness).

@export var duration: float = 5.0


func _on_activate(source: Node) -> void:
	var status := _status_of(source)
	if status != null:
		status.apply(&"sense", 1.0, duration)


func _status_of(entity: Node) -> StatusEffectComponent:
	for child in entity.get_children():
		if child is StatusEffectComponent:
			return child
	return null
