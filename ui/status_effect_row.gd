class_name StatusEffectRow
extends Control
## One spider's active-status-effect badges (UI/HUD overhaul) — one badge
## per active EventBus.status_effect_applied id, showing a color + a local
## countdown that ticks toward zero, removed on
## EventBus.status_effect_expired. Filtered to whichever spider this row is
## bound to via bind_spider().

const STATUS_DISPLAY := {
	&"sense": {"name": "Sense", "color": Color(0.3, 0.75, 0.55)},
	&"venomous": {"name": "Venomous", "color": Color(0.55, 0.25, 0.65)},
	&"poison": {"name": "Poisoned", "color": Color(0.5, 0.8, 0.3)},
	&"silk_haste": {"name": "Silk Haste", "color": Color(0.6, 0.85, 1.0)},
	&"seed_haste": {"name": "Seed Haste", "color": Color(0.85, 0.7, 0.25)},
}

@onready var _row: HBoxContainer = $Row

var _bound_spider: Node = null
var _badges: Dictionary = {}    # StringName -> Label
var _time_left: Dictionary = {} # StringName -> float


## Bind to `spider`. Safe to call again on a fresh spider instance (e.g.
## after a depth descent) — the EventBus connections only attach once.
func bind_spider(spider: Node) -> void:
	for id in _badges.keys().duplicate():
		_remove_badge(id)
	_bound_spider = spider
	if not EventBus.status_effect_applied.is_connected(_on_status_effect_applied):
		EventBus.status_effect_applied.connect(_on_status_effect_applied)
	if not EventBus.status_effect_expired.is_connected(_on_status_effect_expired):
		EventBus.status_effect_expired.connect(_on_status_effect_expired)


func _process(delta: float) -> void:
	for id in _time_left.keys().duplicate():
		_time_left[id] = maxf(0.0, _time_left[id] - delta)
		_update_label(id)


func _on_status_effect_applied(who: Node, id: StringName, _magnitude: float, duration: float) -> void:
	if who != _bound_spider:
		return
	_time_left[id] = duration
	if not _badges.has(id):
		var label := Label.new()
		_row.add_child(label)
		_badges[id] = label
	var display: Dictionary = STATUS_DISPLAY.get(id, {"name": str(id), "color": Color.WHITE})
	_badges[id].modulate = display["color"]
	_update_label(id)


func _on_status_effect_expired(who: Node, id: StringName) -> void:
	if who != _bound_spider:
		return
	_remove_badge(id)


func _update_label(id: StringName) -> void:
	var display: Dictionary = STATUS_DISPLAY.get(id, {"name": str(id), "color": Color.WHITE})
	var label: Label = _badges.get(id)
	if label != null:
		label.text = "%s %.0f" % [display["name"], _time_left.get(id, 0.0)]


func _remove_badge(id: StringName) -> void:
	var label: Label = _badges.get(id)
	if label != null and is_instance_valid(label):
		label.queue_free()
	_badges.erase(id)
	_time_left.erase(id)
