extends CanvasLayer
## In-game HUD: player HP bar, Hunger bar, depth counter. Listens to EventBus so
## it stays decoupled from whichever player instance is current (players are
## recreated each descent).

@onready var health_bar: ProgressBar = $Root/HealthBar
@onready var hunger_bar: ProgressBar = $Root/HungerBar
@onready var depth_label: Label = $Root/DepthLabel


func _ready() -> void:
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.hunger_changed.connect(_on_hunger_changed)
	EventBus.depth_changed.connect(_on_depth_changed)
	EventBus.player_died.connect(_on_player_died)
	_on_depth_changed(GameState.depth)


func _on_health_changed(who: Node, value: float, max_value: float) -> void:
	if who != null and who.is_in_group("player"):
		health_bar.max_value = max_value
		health_bar.value = value


func _on_hunger_changed(who: Node, value: float, max_value: float) -> void:
	if who != null and who.is_in_group("player"):
		hunger_bar.max_value = max_value
		hunger_bar.value = value


func _on_depth_changed(depth: int) -> void:
	depth_label.text = "Depth %d" % depth


func _on_player_died() -> void:
	depth_label.text = "You died — restarting from depth 1…"
