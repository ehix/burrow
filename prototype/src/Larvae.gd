extends Node2D

const TileTypes = preload("res://src/TileTypes.gd").Tile_Type
# Declare member variables here. Examples:
# var a: int = 2
# var b: String = "text"
#var velocity = Vector2.ZERO
var current_dir = Vector2.UP # Default sprite is up
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

export var speed: int = 1

var direction := Vector2.ZERO


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if current_dir != Vector2.ZERO:
		var velocity = current_dir * speed
		global_position += velocity


	
		
func set_direction(new_direction: Vector2):
	if new_direction == Vector2.UP:
#		velocity.y -= 1
		rotation_degrees = 0
		current_dir = Vector2.UP
	elif new_direction == Vector2.RIGHT:
#		velocity.x += 1
		rotation_degrees = 90
		current_dir = Vector2.RIGHT
	elif new_direction == Vector2.DOWN:
#		velocity.y += 1
		rotation_degrees = 180
		current_dir = Vector2.DOWN
	elif new_direction == Vector2.LEFT:
#		velocity.x -= 1
		rotation_degrees = 270
		current_dir = Vector2.LEFT
		
func reverse_direction():
	current_dir = current_dir * -1
	rotation_degrees = (int(rotation_degrees) + 180) % 360


func decide_orientation(tile_type: int):
	print("decide orientation, tile type = ", tile_type)
	if tile_type == TileTypes.TUNNEL_VERTICAL || tile_type == TileTypes.CORNER_BOTTOM_LEFT || tile_type == TileTypes.CORNER_BOTTOM_RIGHT || tile_type == TileTypes.CROSSROAD || tile_type == TileTypes.T_UPSIDE_DOWN:
		set_direction(Vector2.UP)
	elif tile_type == TileTypes.T_NORMAL || tile_type == TileTypes.CORNER_TOP_LEFT || tile_type == TileTypes.CORNER_TOP_RIGHT:
		set_direction(Vector2.DOWN)
	elif tile_type == TileTypes.TUNNEL_HORIZONTAL || tile_type == TileTypes.T_LEFT:
		set_direction(Vector2.RIGHT)
	else:
		set_direction(Vector2.LEFT)
	
func _on_Area2D_area_entered(area: Area2D) -> void:
	print("Larvae hit something! - ", area.get_parent().name)


func _on_Area2D_body_entered(body: Node) -> void:
	print("Larvae body entered something! - ", body.name)
	if "Maze" in body.name:
		reverse_direction()
	if "MapBoundary" in body.name:
		reverse_direction()
	if "Enemy" in body.name:
		queue_free()
		
	if "Player" in body.name:
		queue_free()

