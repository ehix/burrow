class_name CamouflageSkill
extends SkillComponent
## Decoy Spider (female): raises the caster's opacity near-invisible for
## `duration`. Guardrail (strict state exclusion): camouflage breaks the
## instant an attack registers, whether the camouflaged spider lands a hit or
## takes one. `Hurtbox.receive_hit()` calls `break_if_present()` on both the
## hurtbox's own owner (the victim) and the hit's `source` (the attacker) —
## every existing attack path (melee, web shot) already resolves through a
## Hurtbox, so that single call site covers both sides of every attack.

signal broken

@export var target_alpha: float = 0.15
@export var duration: float = 5.0

const OUTLINE_COLOR := Color(0.6, 0.75, 1.0, 0.9)

var active: bool = false

var _visual: CanvasItem
var _time_left: float = 0.0


func _on_activate(source: Node) -> void:
	_visual = _visual_of(source)
	if _visual == null:
		return
	active = true
	_time_left = duration
	_visual.modulate.a = target_alpha
	OutlineFx.set_outline(_visual, true, OUTLINE_COLOR)


func _process(delta: float) -> void:
	super._process(delta)
	if not active:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		break_camouflage()


## MUST be called the instant an attack registers on either side (attacker or
## target) while this spider is camouflaged — never let a camouflaged spider
## land or take a hit while still counted as hidden.
func break_camouflage() -> void:
	if not active:
		return
	active = false
	if _visual != null:
		_visual.modulate.a = 1.0
		OutlineFx.set_outline(_visual, false, OUTLINE_COLOR)
	broken.emit()


func _visual_of(source: Node) -> CanvasItem:
	return source.get_node_or_null("Sprite") as CanvasItem


## Break `entity`'s Camouflage if it has one active. No-op if `entity` is
## null or has no CamouflageSkill child (i.e. almost everything).
static func break_if_present(entity: Node) -> void:
	if entity == null:
		return
	for child in entity.get_children():
		if child is CamouflageSkill:
			child.break_camouflage()
