class_name CamouflageSkill
extends SkillComponent
## Decoy Spider (female): raises the caster's opacity near-invisible for
## `duration`. Guardrail (strict state exclusion): camouflage breaks the
## instant an attack registers, whether the camouflaged spider lands a hit or
## takes one — call `break_camouflage()` from both sides of any attack
## resolution path that can touch a camouflaged spider (Player._melee,
## WebEmitter.fire/WebShot area_entered, Hurtbox.receive_hit). Not yet wired
## into those call sites in this pass.

signal broken

@export var target_alpha: float = 0.15
@export var duration: float = 5.0

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
	broken.emit()


func _visual_of(source: Node) -> CanvasItem:
	return source.get_node_or_null("Sprite") as CanvasItem
