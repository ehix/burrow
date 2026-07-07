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
	if GameState.darkness_enabled:
		# Normal play: follow the player at 1:1 zoom.
		var player := _current_player()
		if player != null:
			camera.global_position = player.global_position
		camera.zoom = Vector2.ONE
	else:
		# Dev overview: centre on the maze and zoom to fit the whole thing.
		_frame_whole_map()


func _frame_whole_map() -> void:
	if not (is_instance_valid(_level) and _level.has_method("map_center")):
		return
	camera.global_position = _level.map_center()
	var view := get_viewport_rect().size
	var map_size: Vector2 = _level.map_pixel_size()
	# Camera2D.zoom > 1 zooms in; pick the axis that keeps the whole map on screen.
	var fit := minf(view.x / map_size.x, view.y / map_size.y) * 0.95
	camera.zoom = Vector2(fit, fit)


func _unhandled_input(event: InputEvent) -> void:
	# Dev toggle (L): remove/restore the fog-of-war darkness and, while off,
	# frame the whole map instead of following the player.
	if event.is_action_pressed("toggle_darkness"):
		GameState.darkness_enabled = not GameState.darkness_enabled
		if is_instance_valid(_level) and _level.has_method("apply_darkness"):
			_level.apply_darkness()
		camera.reset_smoothing() # snap cleanly between follow and overview
	# Dev tool (K): walk through walls. (J): freeze the enemy and larvae.
	elif event.is_action_pressed("dev_noclip"):
		GameState.noclip = not GameState.noclip
	elif event.is_action_pressed("dev_freeze"):
		GameState.freeze_others = not GameState.freeze_others


func _build_level() -> void:
	_level = LevelScene.instantiate()
	add_child(_level)
	_level.build()
	_snap_camera()
	_rebuilding = false


func _snap_camera() -> void:
	if GameState.darkness_enabled:
		var player := _current_player()
		if player != null:
			camera.global_position = player.global_position
			camera.zoom = Vector2.ONE
	else:
		_frame_whole_map()
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
