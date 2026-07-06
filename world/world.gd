extends Node2D
## Root scene. Owns the camera and HUD, builds each Level, and drives the
## descent / permadeath flow off the EventBus (design §4).

const LevelScene := preload("res://world/level.tscn")

@onready var camera: Camera2D = $Camera2D

var _level: Node2D
var _rebuilding := false


func _ready() -> void:
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.player_died.connect(_on_player_died)
	_build_level()


func _process(_delta: float) -> void:
	var player := _current_player()
	if player != null:
		camera.global_position = player.global_position


func _unhandled_input(event: InputEvent) -> void:
	# Dev toggle (L): remove/restore the fog-of-war darkness on the map.
	if event.is_action_pressed("toggle_darkness"):
		GameState.darkness_enabled = not GameState.darkness_enabled
		if is_instance_valid(_level) and _level.has_method("apply_darkness"):
			_level.apply_darkness()


func _build_level() -> void:
	_level = LevelScene.instantiate()
	add_child(_level)
	_level.build()
	_snap_camera_to_player()
	_rebuilding = false


func _snap_camera_to_player() -> void:
	var player := _current_player()
	if player != null:
		camera.global_position = player.global_position
		camera.reset_smoothing()


func _current_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


## Enemy cleared → carry the player's vitals forward and descend to a fresh,
## harder maze.
func _on_enemy_defeated(_cause: String) -> void:
	if _rebuilding:
		return
	var player := _current_player()
	if player != null and player.has_method("store_vitals"):
		player.store_vitals()
	GameState.advance_depth()
	_replace_level()


## Player died → permadeath: reset the run and restart at depth 1.
func _on_player_died() -> void:
	if _rebuilding:
		return
	GameState.start_new_run()
	_replace_level()


func _replace_level() -> void:
	_rebuilding = true
	if is_instance_valid(_level):
		_level.queue_free()
	# Wait for the freed level (and its nodes/groups) to clear before rebuilding.
	await get_tree().process_frame
	_build_level()
