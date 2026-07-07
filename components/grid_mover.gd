class_name GridMover
extends Node
## Animates its parent Node2D one grid tile at a time (4-directional). Used by
## the player, enemy and larva so they all step on the maze grid identically.
##
## Blocking is decided by `block_check` if set, else by the parent body's
## `test_move` — so entities never need the MazeData handed to them. Stepping
## maths live in tick(delta) so they can be unit-tested without physics frames.

signal step_finished

@export var tile_size: int = 48
@export var step_time: float = 0.12

## Multiplies step speed (1.0 = normal). The web slow drops this below 1.
var speed_scale: float = 1.0
## Optional `func(dir: Vector2i) -> bool` — return true to block a step. When
## unset, the parent PhysicsBody2D.test_move is used instead.
var block_check: Callable = Callable()

var _moving := false
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _elapsed := 0.0
var _buffered := Vector2i.ZERO


func _ready() -> void:
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	tick(delta)


func _mover_node() -> Node2D:
	return get_parent() as Node2D


func is_moving() -> bool:
	return _moving


## Begin a one-tile step in a cardinal direction. Buffers and returns false if
## already moving; returns false if blocked; true if a step started.
func try_step(dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO:
		return false
	if _moving:
		_buffered = dir
		return false
	if _is_blocked(dir):
		return false
	var node := _mover_node()
	_from = node.global_position
	_to = _from + Vector2(dir) * float(tile_size)
	_elapsed = 0.0
	_moving = true
	return true


func _is_blocked(dir: Vector2i) -> bool:
	if block_check.is_valid():
		return block_check.call(dir)
	var body := get_parent() as PhysicsBody2D
	if body == null:
		return false
	return body.test_move(body.global_transform, Vector2(dir) * float(tile_size))


func tick(delta: float) -> void:
	if not _moving:
		return
	_elapsed += delta * speed_scale
	var t := clampf(_elapsed / step_time, 0.0, 1.0)
	_mover_node().global_position = _from.lerp(_to, t)
	if t >= 1.0:
		_moving = false
		step_finished.emit()
		if _buffered != Vector2i.ZERO:
			var d := _buffered
			_buffered = Vector2i.ZERO
			try_step(d)


## Slow to `factor` of normal speed for `duration` seconds, then restore.
func apply_slow(factor: float, duration: float) -> void:
	speed_scale = factor
	if is_inside_tree():
		get_tree().create_timer(duration).timeout.connect(
			func() -> void: speed_scale = 1.0)
