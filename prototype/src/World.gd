extends Node2D

const TileTypes = preload("res://src/TileTypes.gd").Tile_Type

var init_timout = 3.0 # DUMMY TIMEOUT
var larvae = preload("res://src/Larvae.tscn")
var num_larvae = 0
onready var Maze = get_node("Maze")
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("enum example - T Left = ",TileTypes.T_LEFT)
	pass # Replace with function body.
	
#func get_input():
#	if Input.is_action_pressed("click"):
#		Maze.get_tiletype_from_worldpos(get_global_mouse_position())
#

func _process(delta: float) -> void:
#	get_input()
	if init_timout > 0:# DUMMY TIMEOUT
		init_timout -= delta# DUMMY TIMEOUT
	else:
		init_timout = 3.0
		if num_larvae < 2:
			spawn_larvae()

func spawn_larvae():
	# DUMMY Larvae spawn
	var larvae_instance = larvae.instance()
	print("Spawn Larvae!")
	var found_valid_tile = false
	var cell_location = Vector2(0, 0)
	while found_valid_tile == false:
		yield(get_tree(), "idle_frame")
		cell_location = Vector2(randi() % Maze.width, randi() % Maze.height)
		var cell_type = Maze.get_cellv(cell_location)
		print("Cell location, Cell type = ", cell_location," ", cell_type)
		if cell_type != Maze.block_tile:
			found_valid_tile = true
	larvae_instance.global_position = ((cell_location * Maze.tile_size) + (Maze.tile_size / 2))
	var target_tiletype = Maze.get_tiletype_from_worldpos(larvae_instance.global_position)
	larvae_instance.decide_orientation(target_tiletype)
	get_tree().get_root().add_child(larvae_instance)
	increment_larvae()

func decrement_larvae():
	num_larvae -=1
func increment_larvae():
	num_larvae += 1
