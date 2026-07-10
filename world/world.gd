extends Node2D
## Root scene. Owns the camera and HUD, builds each Level, and drives the
## descent / permadeath flow off the EventBus (design §4).

const LevelScene := preload("res://world/level.tscn")

## Fraction of missing health restored to the player on a round win — a
## post-victory breather, not a full heal, so health still matters within a
## level but a hard-won fight doesn't bleed straight into the next depth's.
@export var victory_heal_fraction: float = 0.5

@onready var camera: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD

var _level: Node2D
var _rebuilding := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # must keep receiving input to unpause
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
	# Dev tool (R): regenerate the map. (X): remove the wall ahead of the
	# player. (G): toggle player god mode.
	elif event.is_action_pressed("dev_reset_map"):
		_dev_reset_map()
	elif event.is_action_pressed("dev_remove_wall"):
		_dev_remove_wall()
	elif event.is_action_pressed("dev_god_mode"):
		GameState.god_mode = not GameState.god_mode
	elif event.is_action_pressed("dev_playtest_mode"):
		_toggle_playtest_mode()
	# Dev tool (P): flag/clear a pit on the tile ahead — pits have no natural
	# map-generation source yet, so this is how to get one to test ceiling
	# traversal against. (H): force a random eligible hazard now, bypassing
	# HazardDirector's 50-120s base intervals.
	elif event.is_action_pressed("dev_toggle_pit"):
		_dev_toggle_pit()
	elif event.is_action_pressed("dev_trigger_hazard"):
		if is_instance_valid(_level):
			_level.trigger_random_hazard_now()
	# Dev tool (Q): cycle the player through the four spider classes live,
	# for testing each kit without restarting (design §3).
	elif event.is_action_pressed("cycle_class"):
		_cycle_class()
	elif event.is_action_pressed("pause"):
		_toggle_pause()


func _build_level() -> void:
	_level = LevelScene.instantiate()
	# World is PROCESS_MODE_ALWAYS so its own input keeps working while paused;
	# without this explicit override Level would inherit ALWAYS from World too
	# and pausing would freeze nothing at all.
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
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


## Dev tool (R): instantly regenerate the map at the same depth with a fresh
## random layout. Treated as a new spawn — health and hunger reset to defaults
## rather than carrying the player's current vitals forward.
func _dev_reset_map() -> void:
	if _rebuilding:
		return
	GameState.clear_carried_vitals()
	GameState.run_seed = randi()
	_replace_level()


## Dev tool (0): toggles GameState.playtest_mode and drives freeze_enemy/
## god_mode from it together. Off restores both to false regardless of
## whether J/G were separately toggled in between — a one-key preset, not a
## tracked composition of the other two.
func _toggle_playtest_mode() -> void:
	GameState.playtest_mode = not GameState.playtest_mode
	GameState.freeze_enemy = GameState.playtest_mode
	GameState.god_mode = GameState.playtest_mode


## Pause (Esc): freezes gameplay (everything but this node and the HUD, both
## PROCESS_MODE_ALWAYS) and shows a "PAUSED" label.
func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	if hud != null and hud.has_method("set_paused_visible"):
		hud.set_paused_visible(get_tree().paused)


## Dev tool (Q): advance GameState.selected_class to the next of the four
## spider classes and re-apply it to the current player live — no restart or
## level rebuild needed, just a stat/skill-loadout swap on the existing
## instance.
func _cycle_class() -> void:
	var player := _current_player() as Player
	if player == null:
		return
	GameState.selected_class = (GameState.selected_class + 1) % 4
	player.apply_class(GameState.selected_class)
	EventBus.class_changed.emit(GameState.selected_class)


## Dev tool (X): destroy the wall tile directly ahead of the player.
func _dev_remove_wall() -> void:
	var player := _current_player() as Player
	if player == null or not is_instance_valid(_level):
		return
	var target_world := player.global_position + player.facing * float(Level.TILE_SIZE)
	var tile: Vector2i = _level.tile_of(target_world)
	_level.dev_remove_wall_at(tile)


## Dev tool (P): flag/clear a pit on the open tile directly ahead of the
## player, so the ceiling plane's "bypasses ground hazards" behaviour has
## something to demonstrate against.
func _dev_toggle_pit() -> void:
	var player := _current_player() as Player
	if player == null or not is_instance_valid(_level) or _level.maze == null:
		return
	var target_world := player.global_position + player.facing * float(Level.TILE_SIZE)
	var tile: Vector2i = _level.tile_of(target_world)
	if not _level.maze.is_open(tile.x, tile.y):
		return
	_level.set_pit_at(tile, not _level.maze.is_pit(tile.x, tile.y))


## Enemy cleared → a partial victory heal, then carry the player's vitals
## forward and descend to a fresh, harder maze.
func _on_enemy_defeated(_cause: String) -> void:
	if _rebuilding:
		return
	var player := _current_player() as Player
	if player != null:
		var missing := player.health.max_health - player.health.current_health
		player.health.heal(missing * victory_heal_fraction)
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
