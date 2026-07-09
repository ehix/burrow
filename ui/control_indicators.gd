class_name ControlIndicators
extends CanvasLayer
## Debug overlay: lists every player input action and dev-tool toggle with a
## live indicator, so you can visually confirm an input is actually firing.
## Held actions (move, fire) and persistent dev state (noclip, freeze, god
## mode, darkness, pause) stay bright while active; one-shot actions (melee,
## place trap, reset map, remove wall) flash briefly the instant they fire.

const ACTIVE_COLOR := Color(0.45, 1.0, 0.45)
const IDLE_COLOR := Color(0.55, 0.55, 0.55)
const FLASH_TIME := 0.2

class Entry:
	var label: Label
	var check: Callable
	var is_one_shot := false
	var flash_until := 0.0

var _entries: Array[Entry] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # stay live (incl. the Paused row) even while paused

	var root := VBoxContainer.new()
	root.position = Vector2(16, 320)
	add_child(root)

	_add_held(root, "Move (WASD)", func() -> bool:
		return Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down") \
			or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"))
	_add_held(root, "Fire (Space)", func() -> bool: return Input.is_action_pressed("fire"))
	_add_one_shot(root, "Place Trap (E)", "place_trap")
	_add_one_shot(root, "Melee (F)", "melee")
	_add_one_shot(root, "Toggle Darkness (L)", "toggle_darkness")
	_add_held(root, "Noclip (K)", func() -> bool: return GameState.noclip)
	_add_held(root, "Freeze Others (J)", func() -> bool: return GameState.freeze_others)
	_add_one_shot(root, "Reset Map (R)", "dev_reset_map")
	_add_one_shot(root, "Remove Wall (X)", "dev_remove_wall")
	_add_held(root, "God Mode (G)", func() -> bool: return GameState.god_mode)
	_add_one_shot(root, "Toggle Plane (C)", "toggle_plane")
	_add_one_shot(root, "Toggle Pit (P)", "dev_toggle_pit")
	_add_one_shot(root, "Trigger Hazard (H)", "dev_trigger_hazard")
	_add_one_shot(root, "Camouflage (V)", "camouflage")
	_add_one_shot(root, "Sense (N)", "sense")
	_add_one_shot(root, "Remove Walls Skill (M)", "remove_walls_skill")
	_add_held(root, "Paused (Esc)", func() -> bool: return get_tree().paused)


func _add_held(root: VBoxContainer, text: String, check: Callable) -> void:
	var entry := Entry.new()
	entry.label = Label.new()
	entry.label.text = text
	entry.label.modulate = IDLE_COLOR
	entry.check = check
	root.add_child(entry.label)
	_entries.append(entry)


func _add_one_shot(root: VBoxContainer, text: String, action: String) -> void:
	var entry := Entry.new()
	entry.label = Label.new()
	entry.label.text = text
	entry.label.modulate = IDLE_COLOR
	entry.is_one_shot = true
	entry.check = func() -> bool: return Input.is_action_just_pressed(action)
	root.add_child(entry.label)
	_entries.append(entry)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for entry in _entries:
		var active: bool
		if entry.is_one_shot:
			if entry.check.call():
				entry.flash_until = now + FLASH_TIME
			active = now < entry.flash_until
		else:
			active = entry.check.call()
		entry.label.modulate = ACTIVE_COLOR if active else IDLE_COLOR
