extends CanvasLayer
## In-game HUD: player + enemy HP/Hunger bars, depth counter, and a round
## tally (one round = one depth, won by whoever clears it first). Listens to
## EventBus so it stays decoupled from whichever player/enemy instance is
## current (both are recreated each descent).

const PLAYER_WIN_COLOR := Color(0.6, 0.9, 0.55)
const ENEMY_WIN_COLOR := Color(0.9, 0.5, 0.5)
const BANNER_HOLD_TIME := 1.2
const BANNER_FADE_TIME := 0.8

@onready var health_bar: ProgressBar = $Root/HealthBar
@onready var hunger_bar: ProgressBar = $Root/HungerBar
@onready var enemy_health_bar: ProgressBar = $Root/EnemyHealthBar
@onready var enemy_hunger_bar: ProgressBar = $Root/EnemyHungerBar
@onready var depth_label: Label = $Root/DepthLabel
@onready var wins_label: Label = $Root/WinsLabel
@onready var paused_label: Label = $Root/PausedLabel
@onready var round_banner_label: Label = $Root/RoundBannerLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # the "PAUSED" label must show while paused
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.hunger_changed.connect(_on_hunger_changed)
	EventBus.depth_changed.connect(_on_depth_changed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	_on_depth_changed(GameState.depth)
	_update_wins_label()


func set_paused_visible(is_paused: bool) -> void:
	paused_label.visible = is_paused


func _on_health_changed(who: Node, value: float, max_value: float) -> void:
	if who == null:
		return
	if who.is_in_group("player"):
		health_bar.max_value = max_value
		health_bar.value = value
	elif who.is_in_group("enemy"):
		enemy_health_bar.max_value = max_value
		enemy_health_bar.value = value


func _on_hunger_changed(who: Node, value: float, max_value: float) -> void:
	if who == null:
		return
	if who.is_in_group("player"):
		hunger_bar.max_value = max_value
		hunger_bar.value = value
	elif who.is_in_group("enemy"):
		enemy_hunger_bar.max_value = max_value
		enemy_hunger_bar.value = value


func _on_depth_changed(depth: int) -> void:
	depth_label.text = "Depth %d" % depth


## Round win (GameState's own listener already incremented player_wins by the
## time this fires — it connects in its _ready(), which runs before HUD's).
func _on_enemy_defeated(_cause: String) -> void:
	_update_wins_label()
	_show_round_banner("ENEMY DEFEATED!", PLAYER_WIN_COLOR)


## Round loss / permadeath.
func _on_player_died() -> void:
	depth_label.text = "You died — restarting from depth 1…"
	_update_wins_label()
	_show_round_banner("YOU DIED", ENEMY_WIN_COLOR)


func _update_wins_label() -> void:
	wins_label.text = "Wins: You %d - Enemy %d" % [GameState.player_wins, GameState.enemy_wins]


func _show_round_banner(text: String, color: Color) -> void:
	round_banner_label.text = text
	round_banner_label.modulate = Color(color.r, color.g, color.b, 1.0)
	var tween := round_banner_label.create_tween()
	tween.tween_interval(BANNER_HOLD_TIME)
	tween.tween_property(round_banner_label, "modulate:a", 0.0, BANNER_FADE_TIME)
