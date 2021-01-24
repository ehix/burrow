extends KinematicBody2D


enum DIR {
	NORTH,
	EAST,
	SOUTH,
	WEST
}
# Declare member variables here. Examples:
var movespeed: int = 500
var bullet_speed = 2000
#var bullet = preload("res://WebBullet.tscn")
var bullet = preload("res://src/Web.tscn")
var velocity = Vector2.ZERO
var current_dir = Vector2.DOWN
onready var spider_mouth_pos = $SpiderMouth 
var health: int = 3

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

func fire(): 
	var bullet_instance = bullet.instance()
#	add_child(bullet_instance)
	print("fire!")
	bullet_instance.global_position = spider_mouth_pos.global_position
	bullet_instance.set_direction(current_dir)
	
	get_tree().get_root().call_deferred("add_child", bullet_instance)
#	bullet_instance.rotation_degrees = rotation_degrees
#	bullet_instance.apply_impulse(Vector2(), Vector2(bullet_speed, 0).rotated(rotation))
#	bullet_instance.apply_impulse(Vector2(), Vector2(bullet_speed, 0).rotated(deg2rad(270)))
# Called when the node enters the scene tree for the first time.

func _ready() -> void:
	pass # Replace with function body.

func _physics_process(delta: float) -> void:
	get_input()
	velocity = move_and_slide(velocity)
	if Input.is_action_just_pressed("fire"):
		fire()
#	var Player = get_parent().get_node("Player")
#	position += (Player.position - position) / 50
#	look_at(Player.position)
	pass	
	
func die():
	get_tree().reload_current_scene()
	
func take_damage():
	health -= 1
	print("HEALTH - ", health)
	if health == 0:
		die()
	else:
		$AnimationPlayer.play("Damage")

func _on_Area2D_body_entered(body: Node) -> void:
	print("Player Area entered by - ", body.name)
	if "Enemy" in body.name:
		print("Player KILLED by Enemy")
		take_damage()

