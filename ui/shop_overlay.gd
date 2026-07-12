class_name ShopOverlay
extends Control
## Informational upgrade-shop panel (UI/HUD overhaul), toggled by the
## "toggle_shop" action. Lists every UpgradeRegistry entry with its cost,
## dimming rows the player can't yet afford. Purchase still happens via the
## existing buy_upgrade_1..4 keys — this panel never spends runes itself.

const AFFORDABLE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const UNAFFORDABLE_COLOR := Color(0.5, 0.5, 0.5, 1.0)

@onready var _rows: VBoxContainer = $Rows

var _row_labels: Array[Label] = []


func _ready() -> void:
	visible = false
	for upgrade in UpgradeRegistry.ALL:
		var label := Label.new()
		_rows.add_child(label)
		_row_labels.append(label)
	EventBus.runes_changed.connect(func(_total: int) -> void: refresh())
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_shop"):
		toggle()


func toggle() -> void:
	visible = not visible


func refresh() -> void:
	for i in UpgradeRegistry.ALL.size():
		var upgrade := UpgradeRegistry.ALL[i]
		var label := _row_labels[i]
		label.text = "%s — %dr: %s" % [upgrade.display_name, upgrade.rune_cost, upgrade.description]
		label.modulate = AFFORDABLE_COLOR if GameState.runes >= upgrade.rune_cost else UNAFFORDABLE_COLOR
