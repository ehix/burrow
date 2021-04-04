extends Node2D

const TileTypes = preload("res://src/TileTypes.gd").Tile_Type
const creature_timeout_secs = 10
const max_creatures = 3
var creature_timeout = creature_timeout_secs
var larvae = preload("res://src/Larvae.tscn")
var num_larvae = 0
onready var Maze = get_node("Maze")
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("enum example - T Left = ",TileTypes.T_LEFT)
	pass # Replace with function body.
	
func get_input():
	if Input.is_action_pressed("click"):
		var larvaeCount = get_tree().get_nodes_in_group("LARVAE_INSTS").size()
		print(" LARVAE COUNT = ", larvaeCount)
#		Maze.get_tiletype_from_worldpos(get_global_mouse_position())


func _process(delta: float) -> void:
	get_input()
	if creature_timeout > 0:# DUMMY TIMEOUT
		creature_timeout -= delta# DUMMY TIMEOUT
	else:
		creature_timeout = creature_timeout_secs
		if get_tree().get_nodes_in_group("LARVAE_INSTS").size() < max_creatures:
			spawn_larvae()

func spawn_larvae():
	var larvae_instance = larvae.instance()
#	print("Spawn Larvae!")
	# Find a valid tile to put a larvae into
	var found_valid_tile = false
	var cell_location = Vector2(0, 0)
	while found_valid_tile == false:
		yield(get_tree(), "idle_frame")
		cell_location = Vector2(randi() % Maze.width, randi() % Maze.height)
		var cell_type = Maze.get_cellv(cell_location)
		print("Cell location, Cell type = ", cell_location," ", cell_type)
		if cell_type != Maze.block_tile:
			found_valid_tile = true
	# Set position of the larvae to the valid tile location (middle of the tile)
	larvae_instance.global_position = ((cell_location * Maze.tile_size) + (Maze.tile_size / 2))
	# Discover tile type to decide which orientation the larvae should be in
	var target_tiletype = Maze.get_tiletype_from_worldpos(larvae_instance.global_position)
	larvae_instance.decide_orientation(target_tiletype)
	# Add the larvae instance to the world
	get_tree().get_root().add_child(larvae_instance)
	# Keeps track of number of Larvae instances
	larvae_instance.add_to_group("LARVAE_INSTS") 
