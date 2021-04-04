extends Area2D 


# Declare member variables here. Examples:
# var a: int = 2
export var speed: int = 10

var direction := Vector2.ZERO


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if direction != Vector2.ZERO:
		var velocity = direction * speed
		global_position += velocity


	
		
func set_direction(new_direction: Vector2):
	var is_horizontal := false
	if new_direction == Vector2.RIGHT:
		is_horizontal = true
	if new_direction == Vector2.LEFT:
		is_horizontal = true
		
	self.direction = new_direction
	if is_horizontal:
		rotation_degrees = 90
	else:
		rotation_degrees = 0
	


#func _on_Area2D_area_entered(area: Area2D) -> void:
#	print("Bullet hit something! - ", area.get_parent().name)
#


func _on_Area2D_body_entered(body: Node) -> void:
#	print("Bullet body entered something! - ", body.name)
	if "Maze" in body.name:
		queue_free()
		
	if "Enemy" in body.name:
		queue_free()
	
