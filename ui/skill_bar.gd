class_name SkillBar
extends Control
## Two class-skill icons (UI/HUD overhaul): shows the current class's two
## skills' keybind, name, and cooldown countdown. Read-only display —
## activation stays keyboard-only. Re-binds to the new pair whenever the
## player's class changes.

const DIM_COLOR := Color(0.4, 0.4, 0.4, 1.0)
const READY_COLOR := Color(1.0, 1.0, 1.0, 1.0)

@onready var _panel1: Panel = $Slot1
@onready var _key_label1: Label = $Slot1/KeyLabel1
@onready var _name_label1: Label = $Slot1/NameLabel1
@onready var _cooldown_label1: Label = $Slot1/CooldownLabel1
@onready var _panel2: Panel = $Slot2
@onready var _key_label2: Label = $Slot2/KeyLabel2
@onready var _name_label2: Label = $Slot2/NameLabel2
@onready var _cooldown_label2: Label = $Slot2/CooldownLabel2

var _player: Player = null
var _skill1: SkillComponent = null
var _skill2: SkillComponent = null


## Bind to `player`'s current class's two skills, and stay in sync with
## future class changes. Safe to call again on a fresh Player instance
## (e.g. after a depth descent) — the EventBus connection only attaches once.
func bind_player(player: Player) -> void:
	_player = player
	if not EventBus.class_changed.is_connected(_on_class_changed):
		EventBus.class_changed.connect(_on_class_changed)
	_rebind()


func _on_class_changed(_spider_class: int) -> void:
	_rebind()


func _rebind() -> void:
	if _player == null:
		return
	var skills := _player.active_skills()
	var actions := skills.keys()
	var action1: String = actions[0] if actions.size() > 0 else ""
	var action2: String = actions[1] if actions.size() > 1 else ""
	_skill1 = skills.get(action1)
	_skill2 = skills.get(action2)
	_bind_slot(action1, _skill1, _key_label1, _name_label1)
	_bind_slot(action2, _skill2, _key_label2, _name_label2)


func _bind_slot(action: String, skill: SkillComponent, key_label: Label, name_label: Label) -> void:
	if skill == null:
		key_label.text = ""
		name_label.text = ""
		name_label.tooltip_text = ""
		return
	name_label.text = skill.display_name
	name_label.tooltip_text = skill.description
	var events := InputMap.action_get_events(action)
	key_label.text = events[0].as_text_physical_keycode() if events.size() > 0 else ""


func _process(_delta: float) -> void:
	_update_cooldown(_skill1, _panel1, _cooldown_label1)
	_update_cooldown(_skill2, _panel2, _cooldown_label2)


func _update_cooldown(skill: SkillComponent, panel: Panel, cooldown_label: Label) -> void:
	if skill == null:
		return
	var remaining := skill.remaining_cooldown()
	if remaining > 0.0:
		panel.modulate = DIM_COLOR
		cooldown_label.text = "%.1f" % remaining
	else:
		panel.modulate = READY_COLOR
		cooldown_label.text = ""
