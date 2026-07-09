class_name Larva
extends CharacterBody2D
## A wandering creature. Steps cell-to-cell on the maze grid, avoiding an
## immediate reversal unless it is dead-ended. Freezes when a trap catches it,
## and can be killed (not eaten) by a web shot, leaving an inedible corpse.
## Body collides with walls only (mask = world) so it passes through traps and
## spiders until a trap's catch area grabs it.

const CorpseScene := preload("res://entities/web/web_shot_spent.tscn")

@onready var _mover: GridMover = $GridMover
@onready var _sprite: Node2D = get_node_or_null("Sprite")

var caught := false
var _dead := false
var _last_dir := Vector2i.RIGHT


func _ready() -> void:
	add_to_group("larvae")
	_mover.step_finished.connect(_on_step_finished)


## Set initial facing (Level derives this from the spawn tile's type).
func set_facing(dir: Vector2i) -> void:
	if dir != Vector2i.ZERO:
		_last_dir = dir
		rotation = Vector2(dir).angle()


## Called by a trap: stop and snap to the trap centre. Halts the mover first —
## a larva is often caught mid-step (the catch area is wider than a tile), and
## without this the in-flight step keeps lerping toward its pre-capture
## destination on the next frame, dragging the larva right back off-centre.
func set_caught(at_position: Vector2) -> void:
	caught = true
	_mover.stop()
	global_position = at_position


func _physics_process(_delta: float) -> void:
	if caught or _dead or _mover.is_moving() or GameState.freeze_others:
		return
	_wander_step()


## Flash in distress (called when a web catches it).
func flash_distress() -> void:
	CombatFx.flash(_sprite)


## A step landed on a spider's tile: give the larva a tiny visual bump to
## acknowledge the interaction (juice only — mirrors the spider's own shunt
## when it steps onto a larva, never touches the grid position). Compares
## exact tile coordinates rather than a pixel-distance threshold, so it can't
## be missed by any small position drift (e.g. right after a knockback/stun).
func _on_step_finished() -> void:
	var my_tile := _tile_of(global_position)
	for node in get_tree().get_nodes_in_group("spiders"):
		var spider := node as Node2D
		if spider != null and _tile_of(spider.global_position) == my_tile:
			CombatFx.shunt(_sprite, Vector2(_last_dir) * 5.0)
			return


func _tile_of(world: Vector2) -> Vector2i:
	var ts := float(_mover.tile_size)
	return Vector2i(int(floorf(world.x / ts)), int(floorf(world.y / ts)))


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
