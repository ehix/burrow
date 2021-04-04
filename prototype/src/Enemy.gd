extends KinematicBody2D
# Declare member xvariables here. Examples:
# var a: int = 2
# var b: String = "text"
var velocity = Vector2.ZERO
var health = 3
var movespeed: int = 500
var current_dir = Vector2.DOWN
var init_timout = 3.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

func set_position(position):
	var player = get_parent().get_node("Enemy")
	player.position = position

func get_input():
	velocity = Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		velocity.x += 1
		rotation_degrees = 270
		current_dir = Vector2.RIGHT
	if Input.is_action_pressed("move_left"):
		velocity.x -= 1
		rotation_degrees = 90
		current_dir = Vector2.LEFT
	if Input.is_action_pressed("move_down"):
		velocity.y += 1 
		rotation_degrees = 0
		current_dir = Vector2.DOWN
	if Input.is_action_pressed("move_up"):
		velocity.y -= 1
		rotation_degrees = 180
		current_dir = Vector2.UP
	# Make sure diagonal movement isn't faster

	velocity = velocity.normalized() * movespeed


func _physics_process(delta: float) -> void:
#	get_input()
#	if Input.is_action_just_pressed("fire"):
#		fire()
	if init_timout > 0:
		init_timout -= delta
	else:
		var Player = get_parent().get_node("Player")
	#	position += (Player.position - position) / 50
		velocity = (Player.position - position)
	#	velocity = (Player.position - position)
		velocity = move_and_slide(velocity)
		look_at(Player.position)
		rotate(deg2rad(-90))


func die():
		queue_free()
	

func take_damage():
	health -= 1
	print("ENEMY HEALTH - ", health)
	if health == 0:
		die()
	else:
		$AnimationPlayer.play("Damage")
		
#func _on_Area2D_body_entered(body: Node) -> void:
##	print("Enemy body entered ", body.name)
##	pass # Replace with function body.



func _on_Area2D_area_entered(area: Area2D) -> void:
	print("Enemy area entered - ", area.name)
	if "Web" in area.name:
		print("Enemy shot by a web bullet")
		take_damage()

