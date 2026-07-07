class_name Larva
extends CharacterBody2D
## A wandering creature. Steps cell-to-cell on the maze grid, avoiding an
## immediate reversal unless it is dead-ended. Freezes when a trap catches it,
## and can be killed (not eaten) by a web shot, leaving an inedible corpse.
## Body collides with walls only (mask = world) so it passes through traps and
## spiders until a trap's catch area grabs it.

const CorpseScene := preload("res://entities/web/web_shot_spent.tscn")

@onready var _mover: GridMover = $GridMover

var caught := false
var _dead := false
var _last_dir := Vector2i.RIGHT


func _ready() -> void:
	add_to_group("larvae")


## Set initial facing (Level derives this from the spawn tile's type).
func set_facing(dir: Vector2i) -> void:
	if dir != Vector2i.ZERO:
		_last_dir = dir
		rotation = Vector2(dir).angle()


## Called by a trap: stop and snap to the trap centre.
func set_caught(at_position: Vector2) -> void:
	caught = true
	global_position = at_position


func _physics_process(_delta: float) -> void:
	if caught or _dead or _mover.is_moving():
		return
	_wander_step()


func _wander_step() -> void:
	# Prefer any non-reverse direction; fall back to reversing at a dead-end.
	var options: Array[Vector2i] = []
	for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if d != -_last_dir:
			options.append(d)
	options.shuffle()
	options.append(-_last_dir)
	for d in options:
		if _mover.try_step(d):
			_last_dir = d
			rotation = Vector2(d).angle()
			return


## A web shot killed this larva: drop out of the edible pool, leave a corpse.
func web_kill() -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("larvae")
	var holder := get_parent()
	if holder != null:
		var corpse := CorpseScene.instantiate()
		holder.add_child(corpse)
		corpse.global_position = global_position
	queue_free()
