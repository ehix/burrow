class_name SenseSkill
extends SkillComponent
## General utility (design §4): grants temporary `"sense"` status for
## `duration`. The reveal itself (radius-limited outline on nearby spiders/
## larvae, translucent wall highlights) is managed by Level.set_sense_outline()
## called via Player._on_effect_applied/expired.

@export var duration: float = 5.0
## How far from the player (in pixels) the outline reveal reaches — spiders/
## larvae and wall tiles beyond this are untouched.
@export var radius: float = 240.0


func _on_activate(source: Node) -> void:
	var status := _status_of(source)
	if status != null:
		status.apply(&"sense", 1.0, duration)


func _status_of(entity: Node) -> StatusEffectComponent:
	for child in entity.get_children():
		if child is StatusEffectComponent:
			return child
	return null
